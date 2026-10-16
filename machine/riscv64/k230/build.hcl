variable "OUTPUT_DIR" {
  default = "components"
}

variable "CACHE_SCOPE" {
  default = "riscv64-k230"
}

variable "BUILD_REVISION" {
  default = "2"
}

group "release-components" {
  targets = ["buildroot"]
}

target "buildroot" {
  inherits   = ["_buildroot"]
  dockerfile = "machine/riscv64/k230/Dockerfile.sdk"
  target     = "export"

  args = {
    SDK_COMMIT = "fc6cc2151d54cb307be47f81815023f7ffb0eae6"
  }

  output = ["type=local,dest=${OUTPUT_DIR}/buildroot"]

  cache-from = ["type=gha,scope=${CACHE_SCOPE}-buildroot"]
  cache-to   = ["type=gha,mode=max,scope=${CACHE_SCOPE}-buildroot"]
}
