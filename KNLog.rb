# KNLog -- log class by nahi@keynauts.com
# $Id: KNLog.rb,v 1.1 1999/07/03 06:15:55 nakahiro Exp $


# Sample usage1:
#   file = open( 'foo.log', 'a' )
#   logDev = KNLog( file )
#   logDev.add( KNLog::SEV_WARN, 'It is only warning!', 'MyProgram' )
#   ...
#   logDev.close()
#
# Sample usage2:
#   logDev = KNLog( 'logfile.log', 10, 102400 )
#   logDev.add( KNLog::SEV_CAUTION, 'It is caution!', 'MyProgram' )
#   ...
#   logDev.close()
#
# Sample usage3:
#   logDev = KNLog( STDERR )
#   logDev.add( KNLog::SEV_FATAL, 'It is fatal error...' )
#   ...
#   logDev.close()
#
# Log format:
#   SeverityID, [ Date Time MicroSec #pid] SeverityLabel -- ProgName: message
#
# Sample:
#   I, [Wed Mar 03 02:34:24 JST 1999 895701 #19074]  INFO -- Main: Only info.


###
## KNLog -- log class
#
class KNLog # throw KNLog::Error
  require 'kconv'

public
  class Error < RuntimeError; end
  class ShiftingError < Error; end

  # Logging severity.
  SEV_DEBUG = 0	    # Debug level
  SEV_INFO = 1
  SEV_WARN = 2
  SEV_ERROR = 3
  SEV_CAUTION = 4
  SEV_FATAL = 5
  SEV_ANY = 6

  # Japanese Kanji characters' encoding scheme of logfile.
  #   Kconv::EUC, Kconv::JIS, or Kcode::SJIS.
  attr( :kCode, TRUE )

  # Logging severity threshold.
  attr( :sevThreshold, TRUE )

  # - SYNOPSIS
  #     add(
  #       severity,   # Severity. See above to give this.
  #	  comment,    # Message String.
  #	  program     # Program name String.
  #     )
  #
  # - DESCRIPTION
  #     Log a log if the given severity is enough severe.
  #
  # - BUGS
  #	Logfile is not locked.
  #     Append open does not need to lock file.
  #     But on the OS which supports multi I/O, records possibly be mixed.
  #
  # - RETURN
  #     true if succeed, false if failed.
  #     When the given severity is not enough severe,
  #     Log no message, and returns true.
  #
  def add( severity, comment, program = '_unknown_' )
    return true if ( severity < @sevThreshold )
    if ( @logDev.shiftLog? ) then
      begin
      	@logDev.shiftLog
      rescue
	raise KNLog::ShiftingError.new( "Shifting failed. #{$!}" )
      end
      @logDev.dev = createLogFile( @logDev.fileName )
    end
    severityLabel = formatSeverity( severity )
    timestamp = formatDatetime( Time.now )
    comment = formatComment( comment )
    message = formatMessage( severityLabel, timestamp, comment, program )
    @logDev.write( message )
    true
  end

  # - SYNOPSIS
  #     close()
  #
  # - DESCRIPTION
  #     Close the logging device.
  #
  # - RETURN
  #     Always nil.
  #
  def close()
    @logDev.close()
    nil
  end

private
  ###
  ## KNLog::LogDev -- log device class. Output and shifting of log.
  #
  class LogDev
  public
    attr( :dev, TRUE )
    attr( :fileName, TRUE )
    attr( :shiftAge, TRUE )
    attr( :shiftSize, TRUE )

    def write( message )
      # Maybe OS seeked to the last automatically,
      #  when the file was opened with append mode...
      @dev.syswrite( message ) 
    end

    def close()
      @dev.close()
    end

    def shiftLog?
      ( @fileName && ( @shiftAge > 0 ) && ( @dev.stat[7] > @shiftSize ))
    end

    def shiftLog
      # At first, close the device if opened.
      if ( @dev ) then
	@dev.close
	@dev = nil
      end
      ( @shiftAge-3 ).downto( 0 ) do |i|
      	if ( FileTest.exist?( "#{@fileName}.#{i}" )) then
	  File.rename( "#{@fileName}.#{i}", "#{@fileName}.#{i+1}" )
      	end
      end
      File.rename( "#{@fileName}", "#{@fileName}.0" )
      true
    end

  private
    def initialize( dev = nil, fileName = nil )
      @dev = dev
      @fileName = fileName
      @shiftAge = nil
      @shiftSize = nil
    end
  end

  # - SYNOPSIS
  #     KNLog.new(
  #       log,        # String as filename of logging.
  #		      #	 or
  #		      # IO as logging device(i.e. STDERR).
  #	  shiftAge,   # Num of files you want to keep aged logs.
  #	  shiftSize   # Shift size threshold.
  #     )
  def initialize( log, shiftAge = 3, shiftSize = 102400 )
    @logDev = nil
    if ( log.is_a?( IO )) then
      # IO was given. Use it as a log device.
      @logDev = LogDev.new( log )
    elsif ( log.is_a?( String )) then
      # String was given. Open the file as a log device.
      dev = if ( FileTest.exist?( log.to_s )) then
          open( log.to_s, "a" )
      	else
	  createLogFile( log.to_s )
      	end
      @logDev = LogDev.new( dev, log )
    else
      raise ArgumentError.new( 'Wrong argument(log)' )
    end
    @logDev.shiftAge = shiftAge
    @logDev.shiftSize = shiftSize
    @sevThreshold = SEV_DEBUG
    @kCode = Kconv::EUC
  end

  def createLogFile( fileName )
    logDev = open( fileName, 'a' )
    addLogHeader( logDev )
    logDev
  end

  def addLogHeader( file )
    file.syswrite( "# Logfile created on %s by %s\n" %
      [ Time.now.to_s, ProgName ])
  end

  %q$Id: KNLog.rb,v 1.1 1999/07/03 06:15:55 nakahiro Exp $ =~ /: (\S+),v (\S+)/
  ProgName = "#{$1}/#{$2}"

  # Severity label for logging. ( max 5 char )
  SEV_LABEL = %w( DEBUG INFO WARN ERROR CAUTN FATAL ANY );

  def formatSeverity( severity )
    SEV_LABEL[ severity ] || 'UNKNOWN'
  end
  module_function :formatSeverity
  private_class_method :formatSeverity

  def formatDatetime( dateTime )
    dateTime.to_s << ' ' << "%6d" % dateTime.usec
  end
  module_function :formatDatetime
  private_class_method :formatDatetime

  def formatComment( comment )
    newComment = comment.dup
    # Remove white characters at the end of line.
    newComment.sub!( '/[ \t\r\f\n]*$/', '' )
    # Japanese Kanji char code conversion.
    Kconv::kconv( newComment, @kCode, Kconv::AUTO )
    newComment
  end
  module_function :formatComment
  private_class_method :formatComment

  def formatMessage( severity, timestamp, comment, program )
    message = '%s, [%s #%d] %5s -- %s: %s' << "\n"
    message % [ severity[ 0 .. 0 ], timestamp, $$, severity, program, comment ]
  end
  module_function :formatMessage
  private_class_method :formatMessage
end
