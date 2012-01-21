# socket_proxy.rb -- Creates I/O pipes for TCP socket tunneling.
# Copyright (C) 1999-2001, 2003 NAKAMURA, Hiroshi

# This application is copyrighted free software by NAKAMURA, Hiroshi.
# You can redistribute it and/or modify it under the same term as Ruby.

# Ruby bundled library
require 'socket'
require 'logger'

class SocketProxy < Logger::Application
  module Dump
    # Written by Arai-san and published at [ruby-list:31987].
    # http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-list/31987
    def hexdump(str)
      offset = 0
      result = []
      while raw = str.slice(offset, 16) and raw.length > 0
        # data field
        data = ''
        for v in raw.unpack('N* a*')
          if v.kind_of? Integer
            data << sprintf("%08x ", v)
          else
            v.each_byte {|c| data << sprintf("%02x", c) }
          end
        end
        # text field
        text = raw.tr("\000-\037\177-\377", ".")
        result << sprintf("%08x  %-36s  %s", offset, data, text)
        offset += 16
        # omit duplicate line
        if /^(#{ Regexp.quote(raw) })+/n =~ str[offset .. -1]
          result << sprintf("%08x  ...", offset)
          offset += $&.length
          # should print at the end
          if offset == str.length
            result << sprintf("%08x  %-36s  %s", offset-16, data, text)
          end
        end
      end
      result
    end
    module_function :hexdump
  end

  include Logger::Severity
  include Socket::Constants

  attr_accessor :dump_request
  attr_accessor :dump_response

private

  Timeout = 100			# [sec]
  ReadBlockSize = 10 * 1024	# [byte]

  class SessionPool
    def initialize
      @pool = []
      @sockets = []
    end

    def sockets
      @sockets
    end

    def each
      @pool.each do |i|
	yield i
      end
    end

    def add(svrsock, clntsock)
      @pool.push(Session.new(svrsock, clntsock))
      @sockets.push(svrsock, clntsock)
    end

    def del(session)
      @pool.delete(session)
      @sockets.delete(session.server)
      @sockets.delete(session.client)
    end

  private

    class Session
      attr(:server)
      attr(:client)

      def closed?
        @server.closed? and @client.closed?
      end

      private

      def initialize(server = nil, client = nil)
      	@server = server
      	@client = client
      end
    end
  end

  class ListenSocketHash < Hash
    def sockets
      keys
    end
  end

  AppName = File.basename(__FILE__)
  ShiftAge = 0
  ShiftSize = 0

  def initialize(destname, portpairs)
    super(AppName)
    set_log(AppName + '.log', ShiftAge, ShiftSize)
    @log.level = Logger::INFO
    @destname = destname
    @portpairs = portpairs
    @dump_request = true
    @dump_response = false
    @sessionpool = SessionPool.new
    @waitsockets = nil
  end

  def init_waitsockets
    @waitsockets = ListenSocketHash.new
    @portpairs.each do |srcport, destport|
      wait = if is_for_tcp(srcport)
	  TCPServer.new(srcport.to_i)
	else
	  UNIXServer.new(srcport)
	end
      @waitsockets[wait] = [srcport, destport]
      dump_start(srcport, destport)
    end
  end

  def terminate_waitsockets
    @waitsockets.each do |sock, portpair|
      sock.close
      srcport, destport = portpair
      File.unlink(srcport) unless is_for_tcp(srcport)
      dump_end(srcport, destport)
    end
  end

  def is_for_tcp(srcport)
    srcport.to_i != 0
  end

  def run
    begin
      init_waitsockets
      while true
	readwait = @sessionpool.sockets + @waitsockets.sockets
        readready, = IO.select(readwait, nil, nil, Timeout)
        next unless readready
        readready.each do |sock|
	  if (portpair = @waitsockets[sock])
	    newsock = sock.accept
	    dump_accept(newsock.peeraddr[2], portpair)
	    if !add_session(newsock, portpair)
      	      log(WARN) { 'Closing server socket...' }
	      newsock.close
	    end
	  else
	    @sessionpool.each do |session|
	      if sock.equal?(session.server)
		transfer(session, true)
		next
	      elsif sock.equal?(session.client)
		transfer(session, false)
		next
	      end
	    end
	  end
	end
      end
    ensure
      terminate_waitsockets
    end
  end

  def transfer(session, is_server)
    readsock = nil
    writesock = nil
    if is_server
      readsock = session.server
      writesock = session.client
    else
      readsock = session.client
      writesock = session.server
    end

    readbuf = nil
    begin
      readbuf = readsock.sysread(ReadBlockSize)
    rescue IOError
      # not opend for reading
      close_session(session, readsock, writesock)
      return
    rescue EOFError
      close_session(session, readsock, writesock)
      return
    rescue Errno::ECONNRESET
      log(INFO) { "#{$!} while reading." }
      close_session(session, readsock, writesock)
      return
    rescue
      log(WARN) { "Detected an exception. Stopping ..." }
      log(WARN) { $! }
      log(WARN) { $@ }
      close_session(session, readsock, writesock)
      return
    end

    if is_server
      dump_transfer_data(true, readbuf) if @dump_request
    else
      dump_transfer_data(false, readbuf) if @dump_response
    end

    writesize = 0
    while (writesize < readbuf.size)
      begin
      	writesize += writesock.syswrite(readbuf[writesize..-1])
      rescue Errno::ECONNRESET
      	log(INFO) { "#{$!} while writing." }
	log(INFO) { $@ }
        close_session(session, readsock, writesock)
      	return
      rescue
	log(WARN) { "Detected an exception. Stopping ..." }
	log(WARN) { $@ }
        close_session(session, readsock, writesock)
	return
      end
    end
  end

  def add_session(svrsock, portpair)
    srcport, destport = portpair
    begin
      clntsock = TCPSocket.new(@destname, destport)
    rescue
      log(ERROR) { 'Create client socket failed.' }
      return
    end
    @sessionpool.add(svrsock, clntsock)
    dump_add_session(portpair)
  end

  def close_session(session, readsock, writesock)
    readsock.close_read
    writesock.close_write
    if session.closed?
      @sessionpool.del(session)
      dump_close_session
    end
  end

  def dump_start(srcport, destport)
    log(INFO) { 'Started ... src=%s, dest=%s@%s' % [srcport, destport, @destname] }
  end

  def dump_accept(from, portpair)
    log(INFO) {
      srcport, destport = portpair
      "Accepted ... src=%s from %s" % [srcport, from]
    }
  end

  def dump_add_session(portpair)
    log(INFO) {
      srcport, destport = portpair
      'Connection established ... src=%s dest=%s@%s' % [srcport, destport, @destname]
    }
  end

  def dump_transfer_data(is_src2dest, data)
    if is_src2dest
      log(INFO) { 'Transfer data ... [src] -> [dest]' }
    else
      log(INFO) { 'Transfer data ... [src] <- [dest]' }
    end
    dump_data(data)
  end

  def dump_data(data)
    log(INFO) { "Transferred data;\n" << Dump.hexdump(data).join("\n") }
  end

  def dump_close_session
    log(INFO) { 'Connection closed.' }
  end

  def dump_end(srcport, destport)
    log(INFO) { 'Stopped ... src=%s, dest=%s@%s' % [srcport, destport, @destname] }
  end
end
