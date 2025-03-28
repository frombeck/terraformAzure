# terraformAzure
Explanation

main.tf: This file contains the core Terraform configuration. It defines the Azure resources to be created, including the resource group, virtual network, subnet, network security group, and the virtual machines for the Docker Swarm master and worker nodes. It also has the provisioner block to install Docker and initialize the Swarm.
variables.tf: This file defines the variables used in main.tf, such as the resource group name, location, VM size, and SSH public key. This allows you to customize the deployment without modifying the main configuration file directly.
Key Points

You'll need to replace the ~/.ssh/id_rsa path in the provisioner with the actual path to your SSH private key.
The code uses Ubuntu 18.04 LTS as the base image. You can change this in the source_image_reference block if needed.
The network security group rules allow SSH access and the necessary ports for Docker Swarm communication (2376, 2377, 7946, and 4789 for both TCP and UDP).
The provisioner "remote-exec" block is used to install Docker and initialize/join the Swarm on the VMs. This is a simple approach, but for more complex deployments, you might want to use a configuration management tool like Ansible.
