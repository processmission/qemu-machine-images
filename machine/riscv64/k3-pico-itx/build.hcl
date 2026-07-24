variable "OUTPUT_DIR" {
  default = "components"
}

variable "CACHE_SCOPE" {
  default = "riscv64-k3-pico-itx"
}

variable "BUILD_REVISION" {
  default = "2"
}

group "release-components" {
  targets = ["sdk", "eweos"]
}

target "sdk" {
  context    = "."
  dockerfile = "machine/riscv64/k3-pico-itx/Dockerfile.sdk"
  target     = "export"

  output = [
    "type=local,dest=${OUTPUT_DIR}/sdk",
  ]

  cache-from = [
    "type=gha,scope=${CACHE_SCOPE}-sdk",
  ]

  cache-to = [
    "type=gha,mode=max,scope=${CACHE_SCOPE}-sdk",
  ]
}

target "eweos" {
  context    = "."
  dockerfile = "machine/riscv64/k3-pico-itx/Dockerfile.eweos"
  target     = "export"

  output = [
    "type=local,dest=${OUTPUT_DIR}/eweos",
  ]

  cache-from = [
    "type=gha,scope=${CACHE_SCOPE}-eweos",
  ]

  cache-to = [
    "type=gha,mode=max,scope=${CACHE_SCOPE}-eweos",
  ]
}
