require 'rubygems'
Gem::Specification.new { |s|
  s.name = 'socket_proxy'
  s.version = '1.0.0'
  s.date = '2012-01-22'
  s.author = 'Hiroshi Nakamura'
  s.email = 'nahi@ruby-lang.org'
  s.homepage = 'http://github.com/nahi/socket_proxy'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Creates I/O pipes for TCP socket tunneling.'
  s.files = Dir.glob('{lib,bin,sample}/**/*') + ['README']
  s.require_path = 'lib'
  s.executables = ['socket_proxy']
}
