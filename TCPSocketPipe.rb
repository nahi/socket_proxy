#!/usr/bin/env ruby

RCS_ID = %q$Id: TCPSocketPipe.rb,v 1.2 1999/07/03 10:26:56 nakahiro Exp $

require 'socket'
require 'getopts'
require 'KNLog.rb'

class TCPSocketPipe
  include Socket::Constants

  Timeout = 100			# [sec]
  ReadBlockSize = 10 * 1024	# [byte]

  class SessionPool
    class Session
      attr( :server )
      attr( :client )
      def initialize( server = nil, client = nil )
      	@server = server
      	@client = client
      end
    end

    def initialize()
      @pool = []
    end

    def each()
      @pool.each do |i|
	yield i
      end
    end

    def add( serverSock, clientSock )
      @pool.push( Session.new( serverSock, clientSock ))
    end

    def del( session )
      @pool.delete_if do |i|
        session.equal?( i )
      end
    end
  end

  def initialize( srcPort, destName, destPort, log, options )
    @srcPort = srcPort.to_i or raise ArgumentError()
    @destName = destName or raise ArgumentError()
    @destPort = destPort.to_i or raise ArgumentError()
    @log = log
    @options = options
    @sessionPool = SessionPool.new()
    begin
      @waitSock = TCPserver.new( @srcPort )
      @log.add( KNLog::SEV_INFO,
      	'Started ... SrcPort=%s, DestName=%s, DestPort=%s' %
      	[ @srcPort, @destName, @destPort ], self.type )
      run()
    rescue
      @log.add( KNLog::SEV_WARN,
      	"Detected an exception. Stopping ... #{$!}\n" << $@.join( "\n" ),
	self.type )
      raise
    ensure
      @waitSock.close() if @waitSock
      @log.add( KNLog::SEV_INFO,
      	'Stopped ... SrcPort=%s, DestName=%s, DestPort=%s' %
      	[ @srcPort, @destName, @destPort ], self.type )
      @log.close()
    end
  end

  private; def run()
    while true
      readWait = []
      @sessionPool.each do |session|
	readWait.push( session.server ).push( session.client )
      end
      readWait.unshift( @waitSock )
      readReady, writeReady, except = IO.select( readWait, nil, nil, Timeout )
      next unless readReady
      readReady.each do |sock|
	if ( @waitSock.equal?( sock ))
	  newSock = @waitSock.accept
	  @log.add( KNLog::SEV_INFO, "Accepted ... from " <<
	    newSock.peeraddr[2], 'run' )
	  addSession( newSock )
	else
	  @sessionPool.each do |session|
	    transfer( session, true ) if ( sock.equal?( session.server ))
	    transfer( session, false ) if ( sock.equal?( session.client ))
	  end
	end
      end
    end
  end

  private; def transfer( session, bServer )
    readSock = writeSock = nil
    if ( bServer )
      readSock = session.server
      writeSock = session.client
    else
      readSock = session.client
      writeSock = session.server
    end

    readBuf = ''
    begin
      readBuf << readSock.sysread( ReadBlockSize )
    rescue EOFError
      closeSession( session )
      return
    rescue Errno::ECONNRESET
      @log.add( KNLog::SEV_INFO, "#{$!} while reading.", 'transfer' )
      closeSession( session )
      return
    rescue
      @log.add( KNLog::SEV_WARN,
	"Detected an exception. Stopping ... #{$!}\n" << $@.join( "\n" ),
	'transfer' )
      closeSession( session )
      return
    end

    readBuf.sub!( 'Mozilla/4.0 \(compatible; MSIE 4.01; Windows NT\)', 'NaHi SleepyProxy ;-0' )

    if ( bServer )
      @log.add( KNLog::SEV_INFO, 'Transfer data ... [src] -> [dest]',
	'transfer' )
    else
      @log.add( KNLog::SEV_INFO, 'Transfer data ... [src] <- [dest]',
	'transfer' )
    end

    dumpData( readBuf ) if ( bServer or @options[0] )

    writeSize = 0
    while ( writeSize < readBuf.size )
      begin
      	writeSize += writeSock.syswrite( readBuf[writeSize..-1] )
      rescue Errno::ECONNRESET
      	@log.add( KNLog::SEV_INFO, "#{$!} while writing.", 'transfer' )
      	closeSession( session )
      	return
      rescue
      	@log.add( KNLog::SEV_WARN,
	  "Detected an exception. Stopping ... #{$!}\n" << $@.join( "\n" ),
	  'transfer' )
	closeSession( session )
	return
      end
    end
  end

  private; def dumpData( data )
    hexDump = @options[1].to_i
    dumpStr = "Transferred data...\n"
    if ( hexDump )
      charInLine = if ( hexDump == 0 ) then 16 else hexDump end
      lineBuf = ''
      0.upto( data.size - 1 ) do |i|
	lineBuf <<
	  if (( data[i] >= 0x20 ) and ( data[i] <= 0x7f ))
	    data[i, 1]
	  else
	    '.'
	  end
	dumpStr << '%02x ' % ( 0xff & data[i] )
	if ( i % charInLine == ( charInLine - 1 ))
	  dumpStr << "  #{lineBuf}\n" 
	  lineBuf = ''
	end
      end
      dumpStr << "  #{lineBuf}\n"
    else
      dumpStr = data
    end
    @log.add( KNLog::SEV_INFO, dumpStr, 'dumpData' )
  end

  private; def addSession( serverSock )
    begin
      clientSock = TCPsocket.new( @destName, @destPort )
    rescue
      @log.add( KNLog::SEV_ERROR, 'Create client socket failed.', 'addSession' )
      return
    end
    @sessionPool.add( serverSock, clientSock )
    @log.add( KNLog::SEV_INFO, 'Connection established.', 'addSession' )
  end

  private; def closeSession( session )
    session.server.close()
    session.client.close()
    @sessionPool.del( session )
    @log.add( KNLog::SEV_INFO, 'Connection closed.', 'closeSession' )
  end
end

def main()
  getopts( 'd', 'x:' )
  srcPort = ARGV.shift
  destName = ARGV.shift
  destPort = ARGV.shift
  usage() if ( !srcPort or !destName or !destPort )
#  log = KNLog.new( STDERR )
  log = KNLog.new( 'TCPSocketPipe.log', 0 )	# 0 means 'no shifting'
  ap = TCPSocketPipe.new( srcPort, destName, destPort, log, [ $OPT_d, $OPT_x ])
end

def usage()
  STDERR.print <<EOM
Usage: #{$0} srcPort destName destPort

    Creates I/O pipes for TCP socket tunneling.

    srcPort .... port# of a source(on your machine).
    destName ... machine name of a destination(name or ip-addr).
    destPort ... port# of a destination.

    -d ......... dumps data from destination port(not dumped by default).
    -x [num] ... hex dump. formatted num chars in each line.

#{RCS_ID}
EOM
  exit 1
end

main() if ( $0 == __FILE__ )

=begin
    TCPSocketPipe -- Creates I/O pipes for TCP socket tunneling.
    Copyright (C) 1999  NAKAMURA, Hiroshi

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
=end
