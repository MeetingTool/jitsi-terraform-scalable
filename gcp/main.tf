provider "google" {
  project = var.gcp_project
  version = "~> 3.0"
}

provider "random" {
  version = "~> 2.2"
}

resource "random_id" "rnd" {
  byte_length = 4
}

resource "random_id" "jvb_secret" {
  byte_length = 64
}

# External
locals {
  shard_id = var.jitsi_shard.random != "" ? var.jitsi_shard.random : random_id.rnd.hex
  hostname = trimsuffix("meet-${local.shard_id}.${google_dns_managed_zone.default.dns_name}", ".")
  meet_ip = google_compute_instance_from_template.meet.network_interface[0].access_config[0].nat_ip
}

# Internal
locals {
  # [INSTANCE_NAME].c.[PROJECT_ID].internal
  # meet_internal_hostname = "${google_compute_instance_from_template.meet.name}.c.${var.gcp_project}.internal"
  meet_internal_hostname = trimsuffix("meet-${local.shard_id}-internal.${google_dns_managed_zone.default.dns_name}", ".")
  meet_internal_ip = google_compute_instance_from_template.meet.network_interface[0].network_ip
}

resource "google_dns_managed_zone" "default" {
  # Import this resource!
  name = var.dnszone_name
  dns_name = var.dnszone_dnsname
  lifecycle {
    prevent_destroy = true # imported, do not delete
  }
}

resource "google_dns_record_set" "meet-internal" {
  name = "${local.meet_internal_hostname}."
  type = "A"
  ttl  = 300 /* 5 minutes */
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [local.meet_internal_ip]
}

resource "google_dns_record_set" "meet" {
  name = "${local.hostname}."
  type = "A"
  ttl  = 300 /* 5 minutes */
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [local.meet_ip]
}

resource "google_dns_record_set" "meet-auth" {
  name = "auth.${local.hostname}."
  type = "A"
  ttl  = 300 /* 5 minutes */
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [local.meet_internal_ip]
}

locals {
  shared_script = templatefile("${path.module}/scripts/jitsi-shared.sh.tpl", {
    jitsi_hostname = local.hostname
    jitsi_jvbsecret = random_id.jvb_secret.b64_std
  })

  file_nginx_site_conf = replace(file("${path.module}/scripts/nginx.site.conf"), "JITSI_HOSTNAME", local.hostname)
  meet_script = templatefile("${path.module}/scripts/jitsi-meet.sh.tpl", {
    jitsi_hostname = local.hostname
    lets_encrypt_email = var.lets_encrypt_email
    file_nginx_site_conf = local.file_nginx_site_conf
  })

  file_videobridge_config = file("${path.module}/scripts/video-bridge-config.properties")
  file_sip_communicator = file("${path.module}/scripts/sip-communicator.properties")
  jvb_script = templatefile("${path.module}/scripts/jitsi-jvb.sh.tpl", {
    jitsi_hostname = local.hostname
    jitsi_internal_hostname = local.meet_internal_hostname
    jitsi_jvbsecret = random_id.jvb_secret.b64_std
    jitsi_meet_ip = local.meet_ip
    file_videobridge_config = local.file_videobridge_config
    file_sip_communicator = local.file_sip_communicator
  })
}

output "hostname" {
  value = local.hostname
}

output "instance_group_jvb" {
  value = {
    instance_group = module.mig-jvb.instance_group
  }
}

output "logs_cmds" {
  value = {
    meet = "gcloud compute ssh --zone ${var.jitsi_shard.zone} ${google_compute_instance_from_template.meet.name} --project ${var.gcp_project} -- sudo tail -n 100 -f /var/log/prosody/prosody.log /var/log/jitsi/jicofo.log"
  }
}
