#!/home/achilles/nakahiro/bin/ruby
#
# TCP Tunnel
# Copyright (c) 2001 by Michael Neumann (neumann@s-direktnet.de)
#
# $Id: monitor.rb,v 1.1 2001/07/13 04:13:29 nakahiro Exp $
# 
# Modified to use TCPSocketPipe and some tk view.
# Copyright (c) 2001 NAKAMURA Hiroshi.

require 'TCPSocketPipe'
require 'tk'


unless ARGV.size == 3
  puts "USAGE: #$0 srcPort destName destPort"
  puts "  e.g. #$0 8070 localhost 8080"
  exit 1
end

LISTENHOST = 'localhost'
LISTENPORT = ARGV.shift
TUNNELHOST = ARGV.shift
TUNNELPORT = ARGV.shift

WIDTH  = 50
HEIGHT = 35


root = TkRoot.new { title "TCP Tunnel/Monitor: Tunneling #{LISTENHOST}:#{LISTENPORT} to #{TUNNELHOST}:#{TUNNELPORT}" }

top = TkFrame.new(root) {
  pack( 'side' => 'top', 'fill' => 'x' )
}

bottom2 = TkFrame.new(root) {
  pack( 'side' => 'bottom', 'fill' => 'both' )
}

bottom3 = TkFrame.new(bottom2) {
  pack 'side' => 'bottom', 'fill' => 'x'  
}

bottom  = TkFrame.new(bottom2) {
  pack( 'side' => 'top', 'fill' => 'both' )
}

bot_label = TkLabel.new(bottom3) {
  text "Listening for connections on port #{LISTENPORT} for host #{LISTENHOST}"
  pack
}

llabel = TkLabel.new(top) {
  text "From #{LISTENHOST}:#{LISTENPORT}"
  pack 'side' => 'right'
}
rlabel = TkLabel.new(top) {
  text "From #{TUNNELHOST}:#{TUNNELPORT}  "
  pack 'side' => 'left'
}

$ltext  = TkText.new(bottom, 'width' => WIDTH, 'height' => HEIGHT) {
  pack( 'side' => 'left', 'fill' => 'y' )
}
$rtext  = TkText.new(bottom, 'width' => WIDTH, 'height' => HEIGHT) {
  pack( 'side' => 'right', 'fill' => 'y' )
}

scroll = TkScrollbar.new(bottom) {
  command proc { |arg|
    $ltext.yview *arg
    $rtext.yview *arg
  }
  pack( 'side' => 'right', 'fill' => 'y' )
}

$ltext.configure( 'yscrollcommand' => proc { |arg| scroll.set *arg } )
$ltext.yscrollcommand( proc { |arg| scroll.set *arg } )
$rtext.configure( 'yscrollcommand' => proc { |arg| scroll.set *arg } )
$rtext.yscrollcommand( proc { |arg| scroll.set *arg } )

$sessionCount = 0
$sessionResetP = false
TkButton.new(top) {
  text "Clear"
  command {
    $ltext.value = ""
    $rtext.value = "" 
    $sessionResetP = true
  }
  pack
}


class TCPSocketPipe < Application
  def dumpTransferData( isFromSrcToDestP, data )
    if isFromSrcToDestP
      log( SEV_INFO, 'Transfer data ... [src] -> [dest]' )
      $ltext.insert( 'end', data ) unless $sessionResetP
    else
      log( SEV_INFO, 'Transfer data ... [src] <- [dest]' )
      $rtext.insert( 'end', data ) unless $sessionResetP
    end
    dumpData( data )
  end

  def dumpAddSession
    $sessionCount += 1
    str = "--<open: ##{ $sessionCount }>--"
    $ltext.insert( 'end', str + '-' * ( WIDTH - str.size ) << "\n" )
    $rtext.insert( 'end', str + '-' * ( WIDTH - str.size ) << "\n" )
  end

  def dumpCloseSession
    if $sessionResetP
      $sessionCount = 0
      $sessionResetP = false
      return
    end

    str = "--<close: ##{ $sessionCount }>--"
    $ltext.insert( 'end', "\n" << str << '-' * ( WIDTH - str.size ) << "\n" )
    $rtext.insert( 'end', "\n" << str << '-' * ( WIDTH - str.size ) << "\n" )
  end
end

Thread.new {
  app = TCPSocketPipe.new( LISTENPORT, TUNNELHOST, TUNNELPORT )
  app.dumpResponse = true
  app.start()
}

Tk.mainloop
