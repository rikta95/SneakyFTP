#!/usr/bin/env ruby
require "socket"
require 'yaml'
include Socket::Constants

# Volcano FTP constants
BINARY_MODE = 0
ASCII_MODE = 1
MIN_PORT = 1025
MAX_PORT = 65534
MAX_USER = 50

# Volcano FTP class
class VolcanoFtp
  def initialize(config)
    @host = config['bin_adress']
    @port = config['port']
    @flag_connected = true
    @pids = []
    @transfert_type = BINARY_MODE
    @tsocket = nil
    @username = ""
    @password = ""
    @passive = false
    
    # Prepare instance 
    @socket = TCPServer.new(@host, @port)
    @socket.listen(MAX_USER)

    @pids = []
    @transfert_type = BINARY_MODE
    @tsocket = nil
    write_pid_yml(Process.pid)
    puts "Server ready to listen for clients on port #{config["port"]}"
  end
  
  def manage_line(line)
    cmd = line.split(' ')
    case cmd[0]
    when  "USER"
      @cs.write "331 USER OK\r\n"
    when "PASS"
      @cs.write "230 User logged in\r\n"
    when "LIST"
      self.ftp_list(Dir.pwd)
    when "SYST"
      self.ftp_syst(nil)
    when "FEAT"
      @cs.write "211-Extensions supported\r\n211 end\r\n"
    when "PWD"
      self.ftp_pwd(Dir.pwd)
    when "CWD"
      self.ftp_cwd(cmd)
    when "TYPE"
      ftp_type(cmd[1])
    when "PORT"
      ftp_port(cmd[1])
    else
      ftp_502(cmd)
    end
    1
  end

    # Changer le repertoire courrant
  def ftp_cwd(path)
     i = 1
     str = "";
    while i < path.count
      if !(i == 1)
        str = str + " "
      end
      str = str + path[i]
      i+= 1
 end
    begin
      Dir.chdir(str)
      @cs.write "250 Directory successfully changed.\r\t"
    rescue
      @cs.write "550 Failed to change directory.\r\n"
    end
  end

    # Passage en mode active
  def ftp_port(params)
    res = params.split(',')
    port = res[4].to_i * 256 + res[5].to_i
    host = res[0..3].join('.')
    if @data_socket
      @data_socket.close
    end
    begin
      @data_socket = TCPSocket.new(host, port)
      puts "Opened active connection at #{host}:#{port}"
      @passive = false
      @cs.write "200 Connection established (#{port})\r\n"
    rescue
      @cs.write "425 Data connection failed\r\n"
    end
  end
  
  def ftp_type(args)
    if(args == "I")
      @cs.write "200 TYPE is now 8-bit binary\r\n"
    end
    1
  end
  
  def ftp_syst(args)
    @cs.write "215 UNIX Type: L8\r\n"
    1
  end
  def ftp_pwd(params)
    @cs.write "257 \"#{params}\" is the current directory\r\n"
  end
  def ftp_noop(args)
    @cs.write "200 Don't worry my lovely client, I'm here ;)"
    1
  end

  def ftp_502(*args)
    puts args[0][0] + " : Command not found"
    @cs.write "502 Command " + args[0][0] + " not implemented\r\n"
    1
  end

  def ftp_exit(args)
    @cs.write "221 Thank you for using Volcano FTP\r\n"
    0
  end

  def interprete_line(args)
    a = args.split
    func = "ftp_" + a[0]
    begin
      running = send(func,a)
    rescue
      running = send("ftp_502", a)
    end
    running
  end

  def ftp_list(params)
    data_connection do |data_socket|
      if params.nil?
        params = '.'
      end
      output = `ls -al \'#{params}\' 2>&1` 
      result = $?.success?
      if result
        @data_socket.write `ls -al \'#{params}\'`
      else
        @cs.write "501 Failed to list directory.\r\n"
      end
    end
    @data_socket.close if @data_socket
    @data_socket = nil
    @cs.write "226 Transfer complete\r\n"
  end

  # Ouvre la connection permettant de transferer les donnees
  def data_connection(&blk)
    client_socket = nil
    if (@passive)
      unless (IO.select([@data_socket], nil, nil, 60000))
        stattus 425
        return false
      end
      client_socket = @data_socket.accept
      status 150
    else
      client_socket = @data_socket
      status 125
    end
    yield(client_socket)
    return true
  ensure
    client_socket.close if client_socket && @passive
    client_socket = nil
  end

    # Afficher les messages de retour en fonction du code entree en parametre
  def status(code)
    case (code.to_i)
    when 125
      @cs.write "125 Data connection already open; transfer starting.\r\n"
    when 150
      @cs.write "150 File status okay; about to open data connection.\r\n"
    when 200
      @cs.write "200 Command okey.\r\n"
    when 226
      @cs.write "226 Closing data connection.\r\n"
    when 227
      @cs.write "227 Entering Passive Mode.\r\n"
    when 230
      @cs.write "230 User logged in, proceed.\r\n"
    when 250
      @cs.write "250 Requested file action okay, completed.\r\n"
    when 331
      @cs.write "331 User name okay, need password.\r\n"
    when 425
      @cs.write "425 Can't open data connection.\r\n"
    when 500
      @cs.write "500 Syntax error, command unrecognized.\r\n"
    when 501
      @cs.write "501 Syntax error in parameters or arguments\r\n"
    when 502
      @cs.write "502 Command not implemented.\r\n"
    when 530
      @cs.write "530 Not logged in.\r\n"
    when 550
      @cs.write "550 Requested action not taken.\r\n"
    else
      status(code, '')
    end
  end

  def run
    running = 1
    while not running == 0
      selectResult = IO.select([@socket], nil, nil, 0.1)
      if selectResult == nil or selectResult[0].include?(@socket) == false
        @pids.each do |pid|
          if not Process.waitpid(pid, Process::WNOHANG).nil?
            ####
            # Do stuff with newly terminated processes here
            ####
            @pids.delete(pid)
          end
        end
       else
        @cs,  = @socket.accept
        peeraddr = @cs.peeraddr.dup
        @pids << Kernel.fork do
          puts "[#{Process.pid}] Instanciating connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
          @cs.write "220-\r\n\r\n Welcome to Volcano FTP server !\r\n\r\n220 Connected\r\n"
          while not (line = @cs.gets).nil?
            puts "[#{Process.pid}] Client sent : --#{line.strip}--"
            ####
            # Handle commands here
            #running = interprete_line(line)
            #puts running
            ####
            manage_line(line)
          end
          puts "[#{Process.pid}] Killing connection from #{peeraddr[2]}:#{peeraddr[1]}"
          @cs.close
          Kernel.exit!
        end
      end
    end
  end

protected 
  # Protected methods go here
 
  def open_data_transfer(&block)
    client_socket = nil
    if (Thread.current[:passive])
      client_socket = Thread.current[:data_socket].accept
      @cs.write "150 File status OK\r\n"
    else
      client_socket = Thread.current[:data_socket]
      @cs.write "125 File status OK\r\n"
    end
 
    yield(client_socket)
    puts "ok!"
    return true
    ensure
      client_socket.close if client_socket && Thread.current[:passive]
      client_socket = nil    
  end
end

# Usage du script
def usage
  puts "Usage: ruby volcano_ftp.rb start|stop|restart"
end

def start(var_pids)
  if var_pids == "nil"
    begin
      config = begin
        YAML.load(File.open("config/config.yml"))
      rescue ArgumentError => e
        puts "Could not parse YAML: #{e.message}"
      end
    ftp = VolcanoFtp.new(config)
    write_pid_yml(Process.pid)
    ftp.run
    rescue
      write_pid_yml(Process.pid)
      puts "Erreur : #{$!}"
    end
  else
    puts "The server is already running"
  end
end


# MŽthode permettant d'arrter le serveur
def stop(var_pids)
  begin
    if var_pids == "nil"
     puts "No server is running"
    else 
      Process.kill(1, var_pids)
     write_pid_yml("nil")
      puts "Server is closed"
    end
  rescue
  puts "Server not closed properly"
  write_pid_yml("nil")
  end
end

def get_pids_yml
  config = begin
    YAML.load(File.open("config/config.yml"))
  rescue ArgumentError => e
    puts "Could not parse YAML: #{e.message}"
  end
  config['pids']
end

def write_pid_yml(pid)
  config = begin
    YAML.load(File.open("config/config.yml"))
  rescue ArgumentError => e
    puts "Could not parse YAML: #{e.message}"
  end
  config['pids'] = pid
  File.open("config/config.yml", "w") do |f|
    f.puts("port   : #{config['port']}")
    f.puts("bind   : #{config['bind']}")
    f.puts("root_directory   : #{config['root_directory']}")
    f.puts("pids   : #{pid}")
  end
end

# Main
if ARGV[0]
  begin
    case ARGV[0]
    when "start"
        start(get_pids_yml)
    when "stop"
      stop(get_pids_yml)
    when "restart"
      stop(get_pids_yml)
      start(get_pids_yml)
    else
      usage
    end
  rescue SystemExit, Interrupt
    puts "Caught CTRL+C, exiting"
  rescue RuntimeError => e
    puts e
  end
end


