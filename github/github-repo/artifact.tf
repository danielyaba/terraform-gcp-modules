/******************************************
	      Artifact Registry configuration
 *****************************************/
resource "google_artifact_registry_repository" "artifact" {
  # checkov:skip=BC_GCP_GENERAL_29: ADD REASON
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_name
  description   = "Docker repository for micro-service ${var.repository_name}"
  format        = "DOCKER"
}

#####################################################################################

# module "docker_artifact_registry" {
#   source     = "github.com/dapperlabs-platform/terraform-google-artifact-registry?ref=tag"
#   project_id = var.project_id
#   location   = var.location
#   format     = "DOCKER"
#   id         = var.repository_name
#   iam = {
#     "roles/custom_github_cicd" = ["serviceAccount:${google_service_account.service_account.email}"]
#   }
# }
