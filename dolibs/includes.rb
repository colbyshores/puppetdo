require "rubygems"
require "open-uri"
require "json"
require 'net/ssh'
require 'hiera'
require 'puppet'
require 'etc'
require "/etc/puppet/dolibs/dolib.rb"
require "/etc/puppet/dolibs/args.rb"
$scope = YAML.load_file("/etc/puppet/hieradata/common.yaml").values
$hiera = Hiera.new(:config => "/etc/puppet/hiera.yaml")
