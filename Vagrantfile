Vagrant.configure("2") do |config|
  # Use the Debian Bookworm 64-bit box as the base image
  config.vm.box = "utm/bookworm"

  # Forward load balancer port 8080
  config.vm.network "forwarded_port", guest: 8080, host: 8080

  # Forward individual API server ports
  config.vm.network "forwarded_port", guest: 8081, host: 8081
  config.vm.network "forwarded_port", guest: 8082, host: 8082

  # Share directory to synchronize codebase
  config.vm.synced_folder ".", "/vagrant"

  # Run the provision script to install Docker, Docker Compose, and Make
  config.vm.provision "shell", path: "provision.sh"

  # Provider specific configuration (UTM for Apple Silicon)
  config.vm.provider "utm" do |utm|
    utm.directory_share_mode = "virtFS"
    utm.memory = "2048"
    utm.cpus = 2
  end
end
