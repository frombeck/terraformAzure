# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Define variables for customization
variable "resource_group_name" {
  description = "The name of the resource group to create"
  type        = string
  default     = "docker-swarm-rg"
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "East US"
}

variable "virtual_network_name" {
  description = "The name of the virtual network"
  type        = string
  default     = "docker-swarm-vnet"
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
  default     = "docker-swarm-subnet"
}

variable "subnet_address_prefix" {
  description = "The address prefix for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "master_node_count" {
  description = "The number of master nodes"
  type        = number
  default     = 3
}

variable "worker_node_count" {
  description = "The number of worker nodes"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "The size of the virtual machines"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "admin_username" {
  description = "The username for the administrator account"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "The SSH public key for authentication"
  type        = string
}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  address_space       = ["10.0.0.0/16"]
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes       = [var.subnet_address_prefix]
}

# Create a network security group for the swarm
resource "azurerm_network_security_group" "swarm_nsg" {
  name                = "swarm-nsg"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "22"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "DockerSwarm"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_ranges         = ["2376", "2377", "7946", "4789"] # Docker Swarm ports
    destination_port_ranges    = ["2376", "2377", "7946", "4789"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
   security_rule {
    name                       = "DockerSwarmUDP"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_ranges         = ["7946", "4789"] # Docker Swarm ports
    destination_port_ranges    = ["7946", "4789"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create virtual machines for Docker Swarm Masters
resource "azurerm_linux_virtual_machine" "master_nodes" {
  count                 = var.master_node_count
  name                  = "master-node-${count.index}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = var.location
  size                  = var.vm_size
  network_interface_ids = [azurerm_network_interface.master_nic[count.index].id]

  os_disk {
    name              = "master-os-disk-${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name  = "master-${count.index}"
  admin_username = var.admin_username
  disable_password_authentication = true
  ssh_public_key {
    key_data     = var.ssh_public_key
    username     = var.admin_username
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa") # Change to your private key path
      host   = self.public_ip_address
    }

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo usermod -aG docker ${var.admin_username}",
      "sudo systemctl enable docker.service",
      "sudo systemctl start docker.service",
      "if [ ${count.index} -eq 0 ]; then sudo docker swarm init --advertise-addr ${self.private_ip_address}; else sudo docker swarm join --token $(sudo docker swarm join-token manager) ${azurerm_linux_virtual_machine.master_nodes[0].private_ip_address}:2377; fi",
    ]
  }
}

# Create virtual machines for Docker Swarm Workers
resource "azurerm_linux_virtual_machine" "worker_nodes" {
  count                 = var.worker_node_count
  name                  = "worker-node-${count.index}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = var.location
  size                  = var.vm_size
  network_interface_ids = [azurerm_network_interface.worker_nic[count.index].id]

  os_disk {
    name              = "worker-os-disk-${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name  = "worker-${count.index}"
  admin_username = var.admin_username
  disable_password_authentication = true
  ssh_public_key {
    key_data     = var.ssh_public_key
    username     = var.admin_username
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa") # Change to your private key path
      host   = self.public_ip_address
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo usermod -aG docker ${var.admin_username}",
      "sudo systemctl enable docker.service",
      "sudo systemctl start docker.service",
      "sudo docker swarm join --token $(sudo docker swarm join-token worker) ${azurerm_linux_virtual_machine.master_nodes[0].private_ip_address}:2377",
    ]
  }
}

#Create Network interfaces
resource "azurerm_network_interface" "master_nic" {
  count                 = var.master_node_count
  name                  = "master-nic-${count.index}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.master_ip[count.index].id
  }
  network_security_group_id = azurerm_network_security_group.swarm_nsg.id
}

resource "azurerm_network_interface" "worker_nic" {
  count                 = var.worker_node_count
  name                  = "worker-nic-${count.index}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.worker_ip[count.index].id
  }
  network_security_group_id = azurerm_network_security_group.swarm_nsg.id
}

# Create public IPs for the VMs
resource "azurerm_public_ip" "master_ip" {
  count = var.master_node_count
  name                = "master-public-ip-${count.index}"
  resource_group_name  = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Dynamic"
}

resource "azurerm_public_ip" "worker_ip" {
  count = var.worker_node_count
  name                = "worker-public-ip-${count.index}"
  resource_group_name  = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Dynamic"
}


# Output the Swarm details.
output "swarm_master_ips" {
  description = "Public IPs of the Swarm master nodes."
  value       = [for ip in azurerm_public_ip.master_ip : ip.ip_address]
}

output "swarm_worker_ips" {
  description = "Public IPs of the Swarm worker nodes."
  value       = [for ip in azurerm_public_ip.worker_ip : ip.ip_address]
}
