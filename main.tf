# Thiago Marinho da Silva


#PROVIDER
terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

#RESOURCE GROUP
resource "azurerm_resource_group" "rgexercicioterraform" {
    name     = "rgexercicioterraform"
    location = "eastus"

    tags     = {
        "Environment" = "exercicio terraform"
    }
}

#VNET
resource "azurerm_virtual_network" "vnet-exercicioterraform" {
    name                = "vnet-exercicioterraform"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rgexercicioterraform.name
}

#SUBNET
resource "azurerm_subnet" "subnet-exercicioterraform" {
    name                 = "subnet-exercicioterraform"
    resource_group_name  = azurerm_resource_group.rgexercicioterraform.name
    virtual_network_name = azurerm_virtual_network.vnet-exercicioterraform.name
    address_prefixes       = ["10.0.1.0/24"]
}

#IP PUBLICO
resource "azurerm_public_ip" "pubip-exercicioterraform" {
    name                         = "pubip-exercicioterraform"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.rgexercicioterraform.name
    allocation_method            = "Static"
}

#NETWORK SECURITY GROUP
resource "azurerm_network_security_group" "nsg-exercicioterraform" {
    name                = "nsg-exercicioterraform"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rgexercicioterraform.name

    security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

#NETWORK INTERFACE
resource "azurerm_network_interface" "ni-exercicioterraform" {
    name                      = "ni-exercicioterraform"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.rgexercicioterraform.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.subnet-exercicioterraform.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.pubip-exercicioterraform.id
    }
}


resource "azurerm_network_interface_security_group_association" "exercicioterrafor" {
    network_interface_id      = azurerm_network_interface.ni-exercicioterraform.id
    network_security_group_id = azurerm_network_security_group.nsg-exercicioterraform.id
}

data "azurerm_public_ip" "ip_data_db" {
  name                = azurerm_public_ip.pubip-exercicioterraform.name
  resource_group_name = azurerm_resource_group.rgexercicioterraform.name
}

resource "azurerm_storage_account" "stgaexercicioterraform" {
    name                        = "stgaexercicioterraform"
    resource_group_name         = azurerm_resource_group.rgexercicioterraform.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

#VM
resource "azurerm_linux_virtual_machine" "vm-exercicioterraform" {
    name                  = "vm-exercicioterraform"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.rgexercicioterraform.name
    network_interface_ids = [azurerm_network_interface.ni-exercicioterraform.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDiskMySQL"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "myvm"
    admin_username = var.user
    admin_password = var.password
    disable_password_authentication = false

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.stgaexercicioterraform.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.rgexercicioterraform ]
}

#SAÍDA IP PUBLICO
output "public_ip_address_mysql" {
  value = azurerm_public_ip.pubip-exercicioterraform.ip_address
}


resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vm-exercicioterraform]
  create_duration = "30s"
}

#UPLOAD DA PASTA
resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        source = "config"
        destination = "/home/azureuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

#INSTALACAO DO MYSQL
resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/azureuser/config/user.sql",
            "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}