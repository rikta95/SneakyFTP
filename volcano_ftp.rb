#!/usr/bin/env ruby
require "socket"
include Socket::Constants

# Volcano FTP constants
BINARY_MODE = 0
ASCII_MODE = 1
MIN_PORT = 1025
MAX_PORT = 65534
MAX_USER = 50

# Volcano FTP class
class VolcanoFtp
  def initialize(port)#,opts = {}
    # Prepare instance 
    @socket = TCPServer.new("", port)
    @socket.listen(MAX_USER)

    @pids = []
    @transfert_type = BINARY_MODE
    @tsocket = nil
    puts "Server ready to listen for clients on port #{port}"
  end
  
  def manage_line(line)
    cmd = line.split(' ')
    case cmd[0]
    when  "USER"
      @cs.write "331 USER OK\r\n"
    when "PASS"
      @cs.write "230 User logged in\r\n"
    when "LIST"
      self.ftp_list("/")
    when "SYST"
      self.ftp_syst(nil)
    when "FEAT"
      @cs.write "211-Extensions supported\r\n211 end\r\n"
    when "PWD"
      self.ftp_pwd
    when "TYPE"
      ftp_type(cmd[1])
    else
      ftp_502(cmd)
    end
    1
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
  def ftp_pwd
    @cs.write "257 '/' Root path\r\n"
    0
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

  def ftp_list(dir = '.')
	open_data_transfer do |data_socket|
	    puts "toto011"
		list = Thread.current[:cwd].get_list
		puts "toto02"
		data_socket.puts("----" + Thread.current[:cwd].ftp_name + "----")
		puts "toto03"
		list.each {|file| data_socket.puts(file.ftp_size.to_s + "\t" + file.ftp_name + "\r\n");puts file.ftp_name }
		data_socket.puts("----" + Thread.current[:cwd].ftp_name + "----")
	end
	Thread.current[:data_socket].close if Thread.current[:data_socket]
	Thread.current[:data_socket] = nil
 
	@cs.write "200 OK\r\n"
    0
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

end

# Main
if ARGV[0]
  begin
    ftp = VolcanoFtp.new(ARGV[0])#Param === port de convertion
    ftp.run
  rescue SystemExit, Interrupt
    puts "Caught CTRL+C, exiting"
  rescue RuntimeError => e
    puts e
  end
end
