
# define GCP project name
variable "gcp_project" {
  type = string
  default = "internal-interview-candidates"
  description = "GCP project name"
}

variable "app_project" {
  type = string
  default = "internal-interview-candidates"
  description = "GCP project name"
}
# define application name
variable "app_name" {
  type = string
  default = "Web_project"
}


variable "gcp_zone_1" {
  type = string
  default = "us-central1-a"
}
variable "gcp_region_1" {
  type = string
  default = "us-central1"
}
