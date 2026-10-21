variable "OUTPUT_DIR" {
  default = "components"
}

variable "CACHE_SCOPE" {
  default = "riscv64-k230"
}

variable "BUILD_REVISION" {
  default = "1"
}

group "release-components" {
  targets = ["sdk"]
}

target "sdk" {
  context    = "."
  dockerfile = "machine/riscv64/k230/Dockerfile.sdk"
  target     = "export"

  args = {
    SDK_COMMIT = "fc6cc2151d54cb307be47f81815023f7ffb0eae6"
  }

  output = ["type=local,dest=${OUTPUT_DIR}/sdk"]
  cache-from = ["type=gha,scope=${CACHE_SCOPE}-sdk"]
  cache-to   = ["type=gha,mode=max,scope=${CACHE_SCOPE}-sdk"]
}
