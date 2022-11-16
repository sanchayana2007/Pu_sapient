terraform {
  required_version = ">= 0.12"
}

##Creating the provider 

provider "google" {
  project     = "internal-interview-candidates"
}


#Creating the VPC 

#Create a VPC network
resource "google_compute_network" "vpc_network" {
  project                 =  var.gcp_project
  name = "${var.gcp_project}-vpc-123"
  auto_create_subnetworks = "false" 
  routing_mode = "GLOBAL"
}

#creating the subnetwork 

#Set the subnetwork for the IP 
resource "google_compute_subnetwork" "subnet-with-logging" {
  name          = "log-test-subnetwork"
  ip_cidr_range = "10.2.0.0/16"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.name 

}

#Set aup a NAT router and use the IG as teh router 
# create a public ip for nat service
resource "google_compute_address" "nat-ip" {
  name = "web-app-nap-ip"
  project = var.app_project
  region  = var.gcp_region_1
}
# create a nat to allow private instances connect to internet
resource "google_compute_router" "nat-router" {
  name = "web-app-nat-router"
  region        = "us-central1"
  network = google_compute_network.vpc_network.name
}

#Set up Compute router NAT using NAT gateway 
resource "google_compute_router_nat" "nat-gateway" {
  name = "web-app-nat-gateway"
  router = google_compute_router.nat-router.name
  nat_ip_allocate_option = "MANUAL_ONLY"
  region  = var.gcp_region_1
  nat_ips = [ google_compute_address.nat-ip.self_link ]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" 
  depends_on = [ google_compute_address.nat-ip ]
}

output "nat_ip_address" {
  value = google_compute_address.nat-ip.address
}


# allow http traffic
resource "google_compute_firewall" "allow-http" {
  name = "web-app-fw-allow-http"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
 
  source_tags = ["web"]
  target_tags = ["http"]
}


# Create web server template
resource "google_compute_instance_template" "web_server" {
  name = "web-server-template"
  description = "This template is used to create Apache web server"
  instance_description = "Web Server running Apache"
  can_ip_forward = false
  machine_type = "g1-small"
  region  = var.gcp_region_1
  tags = ["ssh","http"]
  scheduling {
    automatic_restart = true
    on_host_maintenance = "MIGRATE"
  }
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-1804-lts"
    auto_delete = true
    boot = true
  }
  
  network_interface {
    network = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet-with-logging.name
  }
  
  lifecycle {
    create_before_destroy = true
  }
  metadata_startup_script = "sudo apt-get update; sudo apt-get install -yq build-essential apache2"
}

resource "google_compute_global_forwarding_rule" "global_forwarding_rule" {
  name = "web-app-global-forwarding-rule"
  project = var.app_project
  target = google_compute_target_http_proxy.target_http_proxy.self_link
  port_range = "80"
}
# used by one or more global forwarding rule to route incoming HTTP requests to a URL map
resource "google_compute_target_http_proxy" "target_http_proxy" {
  name = "web-app-proxy"
  project = var.app_project
  url_map = google_compute_url_map.url_map.self_link
}
# defines a group of virtual machines that will serve traffic for load balancing
resource "google_compute_backend_service" "backend_service" {
  name = "web-app-backend-service"
  project = var.app_project
  port_name = "http"
  protocol = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  health_checks = [google_compute_health_check.healthcheck.id]
  backend {
    group = google_compute_instance_group_manager.web_private_group.instance_group
    balancing_mode = "RATE"
    max_rate_per_instance = 100
  }
}
# creates a group of virtual machine instances
resource "google_compute_instance_group_manager" "web_private_group"{
  name = "web-app-vm-group"
  project = var.app_project
  base_instance_name = "web-app-web"
  zone = var.gcp_zone_1
  version {
    instance_template  = google_compute_instance_template.web_server.id
  }
  named_port {
    name = "http"
    port = 80
  }
}

# used to route requests to a backend service based on rules that you define for the host and path of an incoming URL
resource "google_compute_url_map" "url_map" {
  name = "web-app-load-balancer"
  project = var.app_project
  default_service = google_compute_backend_service.backend_service.self_link
}

# automatically scale virtual machine instances in managed instance groups according to an autoscaling policy
resource "google_compute_autoscaler" "autoscaler" {
  name = "web-app-autoscaler"
  project = var.app_project
  zone = var.gcp_zone_1
  target  = google_compute_instance_group_manager.web_private_group.self_link
  autoscaling_policy {
    max_replicas = var.lb_max_replicas
    min_replicas = var.lb_min_replicas
    cooldown_period = var.lb_cooldown_period
    
    cpu_utilization {
      target = 0.8
    }
  }
}
# show external ip address of load balancer
output "load-balancer-ip-address" {
  value = google_compute_global_forwarding_rule.global_forwarding_rule.ip_address
}

data "google_compute_instance_group" "all" {
    name = "web-app-vm-group"
  zone = var.gcp_zone_1
    
}

output "google_compute_instance_group" {
  value = data.google_compute_instance_group.all
}
#SETTING UP THE LBS

# determine whether instances are responsive and able to do work
resource "google_compute_health_check" "healthcheck" {
   name = "web-app-healthcheck"
   timeout_sec = 1
   check_interval_sec = 1

   http_health_check {
     port = 80
   }
}



variable "lb_max_replicas" {
  type = string
  description = "Maximum number of VMs for autoscale"
  default = "4"
}
# minimum number of VMs for load balancer autoscale
variable "lb_min_replicas" {
  type = string
  description = "Minimum number of VMs for autoscale"
  default = "1"
}
# number of seconds that the autoscaler should wait before it starts collecting information
variable "lb_cooldown_period" {
  type = string
  description = "The number of seconds that the autoscaler should"
  default = "60"
}


resource "google_project_iam_policy" "project" {
  project     = "internal-interview-candidates"
  policy_data = data.google_iam_policy.admin.policy_data
}

data "google_iam_policy" "admin" {
  binding {
    role = "roles/compute.admin"

    members = [
      "xyz@user.com",
    ]
  }
}
