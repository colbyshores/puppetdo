module Puppetdo

  def Puppetdo.dhcpapi(hostquery)
    hosts = Array.new
    content = open("http://dhcp.vvmedia.com/rest/hostname/#{hostquery}").read
    content.each do |content|
      result = JSON.parse("#{content}")
      #if the start of the hostname = the API query with a number after it and somewhere in the hostname is a number and .vvmedia.com then extract those hostnames to a string array called hosts...
      if result["hostname"] =~ /^#{hostquery}[\d+]/ and result["hostname"].match(/[\d+]\.vvmedia\.com/)
        hosts  << result["hostname"]
      end
    end
    return hosts
  end

  def Puppetdo.puppet(puppetquery)
    #put a list if all certificate host names from the second column that starts with the API query followed by a number and followed by .vvmedia.com in to a string array called certs...
    certs = `puppet cert list --all | awk '{ print $2 }' | egrep '^\"#{puppetquery}[[:digit:]]+\.vvmedia\.com'`.delete('"').split(/\n/)
    return certs
  end

  def Puppetdo.process(groupquery)
    #align for auditing all machines
    $flag[:auditall] ? differences =  (Puppetdo.dhcpapi(groupquery) + Puppetdo.puppet(groupquery)).uniq : differences =  Puppetdo.dhcpapi(groupquery) - Puppetdo.puppet(groupquery)
    if $flag[:audit] or $flag[:auditall]
       if differences.to_s != '' or $flag[:auditall]
         $flag[:auditall] ? "Auditing all hosts on #{groupquery}:\n" : "These hosts on the #{groupquery} group do not match Puppet Cert -> DHCP:\n"
         counter = 0
         differences.each do |host|
           Puppetdo.puppet(groupquery).include?(host) ? puppetresult = 'puppetcert->true'.green : puppetresult = 'puppetcert->false'.red
           Puppetdo.dhcpapi(groupquery).include?(host) ? dhcpresult = 'dhcp->true'.green : dhcpresult = 'dhcp->false'.red
           ping(host) ? pingresult = 'ping->true'.green : pingresult = 'ping->false'.red
           puts differences[counter] + " = #{puppetresult}  #{dhcpresult}  #{pingresult}"
           counter += 1
         end
         puts "\n\n"
       end
    else
      processing(groupquery)
    end
  end
end

def processing(groupquery)
  scope = YAML.load_file("/etc/puppet/hieradata/common.yaml").values
  hiera = Hiera.new(:config => "/etc/puppet/hiera.yaml")

  hostlist = Puppetdo.puppet(groupquery)
  if hostlist.to_s != ''
    puts "Processing #{groupquery} hosts...\n"
    hostlist.each do |hostname|
      begin
        puts "starting... #{hostname}"
        ssh = Net::SSH.start(hostname, 'root')
        if $flag[:noop] 
          sshcommand = "puppet agent --test --noop"
        else


          #only execute deploytag if deploy config is in place
          configpath = "#{hiera.lookup("web::scripts","/",scope)}/export_code.pp"
          svnserver = hiera.lookup("repo::svnserver","/",scope)
          deploy = ssh.exec!("test -f #{configpath}; echo $?").to_i
          if deploy == 0  #ensure deploy script is in place.  Part of the web module web/template/export_code.pp.erb
            if $flag[:deploytag]
                filecount_before = ssh.exec!("svn ls #{svnserver}/#{$flag[:deploytag]} | wc -l").to_i
                puts "Starting Deployment.  Shutting down Apache and removing from load balancer..."
                ssh.exec!("/etc/init.d/apache2 stop; sleep 15; rm /home/httpd/arch/public/smallsites/default/test.html")
                res = ssh.exec!("FACTER_SVNSERVER=#{svnserver}; export FACTER_SVNSERVER; FACTER_DEPLOYTAG=#{$flag[:deploytag]}; export FACTER_DEPLOYTAG; puppet apply #{configpath} --verbose")
                filecount_after = ssh.exec!("ls -A /home/httpd/arch/ | wc -l").to_i
                puts "files on SVN: #{filecount_before}"
                puts res
                puts "files on /home/httpd/arch after deployment: #{filecount_after}"
                counter = 1
                while filecount_before != filecount_after do
                  puts "iterated #{counter} of 3"

                  res = ssh.exec!("FACTER_SVNSERVER=#{svnserver}; export FACTER_SVNSERVER; FACTER_DEPLOYTAG=#{$flag[:deploytag]}; export FACTER_DEPLOYTAG; puppet apply #{configpath} --verbose")
                  filecount_after = ssh.exec!("ls -A /home/httpd/arch/ | wc -l").to_i
                  puts "files on SVN: #{filecount_before}"
                  puts res
                  puts "files on /home/httpd/arch after deployment: #{filecount_after}"
                  if counter != 2 
                    counter += 1
                  else
                    puts "Quitting after 3 failed attempts on #{hostname}!"
                    exit 1
                  end
                end
                puts "Deployment Successful! Starting Apache and then renabling load balancer." 
                ssh.exec!("cp /srv/www/htdocs/index.html /home/httpd/arch/public/smallsites/default/test.html; sleep 5; /etc/init.d/apache2 start")


              end         
            else
              if !$flag[:deploytag]
                sshcommand = "puppet agent --test"
                res = ssh.exec!(sshcommand)
              else
                puts "#{configpath} not found for deployment..."
              end
          end


        end
        ssh.close
        if $flag[:verbose] or $flag[:noop]
          puts res
        end
      rescue
        puts "Unable to connect to #{hostname}"
      end
      puts "finished... #{hostname}\n\n"
      sleep 1
    end
  end
end

def ping(host, timeout=5, service="echo")
  begin
    timeout(timeout) do
      s = TCPSocket.new(host, service)
      s.close
    end
  rescue Errno::ECONNREFUSED
    return true
  rescue Timeout::Error, StandardError
    return false
  end
end
