def args(argv0, argv1, argv2, argv3 = nil)
  case argv0
    when "-c"
      detectsudo
      argv3 ? argvflags(argv2,argv3) : argvflags(argv2)
      confirm(argv1)
      return argv1
    when "--cluster"
      detectsudo
      argv3 ? argvflags(argv,argv3) : argvflags(argv2)
      confirm(argv1)
      return argv1
    when "-h"
      helpinfo
    when "--help"
      helpinfo
    when nil 
      helpinfo
      exit 0
  end 
end

def helpinfo
  puts  "-c clustername  or  --cluster clustername\n"\
        "to process cluster group stored in /etc/puppet/puppetdo\n"\
        "add --verbose or -v to the end for verbose output\n\n"\
        "add --deploy or -d and then the tag(ex RELEASE-20140916) for code deployments\n\n"\
        "-c/--cluster with --noop to the end for cluster noop\n\n"\
        "To audit the server cluster to determine\n"\
        "Puppet cert -> dhcp mismatches use\n"\
        "-c/--cluster clustername -a or -c/--cluster custername --audit\n\n"\
        "To audit all hosts in a cluster use\n"\
        "-c/--cluster clustername -all \n\n\n"
end

def confirm(argv1)
  requestprocess = false
  $flag.each { |value| requestprocess = value ? true : false } 
  if !requestprocess
    puts "About to process #{argv1} cluster.  Are you sure? Y/N\n"
    while true
      case $stdin.gets.strip
        when 'Y', 'y', 'yes'
          break
        when /\A[nN]o?\Z/ #n or no
          exit 0
      end
    end
  end
end

def detectsudo
  if Process.euid != 0 #process config change only if running as root
    puts "This application must be run as Sudo or Root\n\n\n"
    exit 1
  end
end

def argvflags(argv, argv3 = nil)
  $flag = Hash.new
  case argv
    when "--verbose"
      $flag[:verbose] = true
    when "-v"
      $flag[:verbose] = true
    when "-d"
      confirm('web')
      $flag[:deploytag] = argv3
    when "--deploy"
      confirm('web')
      $flag[:deploytag] = argv3
    when "--audit"
      $flag[:audit] = true
    when "-a"
      $flag[:audit] = true
    when "--auditall"
      $flag[:auditall] = true
    when "--noop"
      $flag[:noop] = true
  end
end
