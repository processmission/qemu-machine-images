variable "OUTPUT_DIR" {
  default = "components"
}

variable "CACHE_SCOPE" {
  default = "riscv64-microchip-icicle-kit"
}

group "release-components" {
  targets = ["hss", "buildroot"]
}

target "hss" {
  context    = "."
  dockerfile = "machine/riscv64/microchip-icicle-kit/Dockerfile.hss"
  target     = "export"

  output = [
    "type=local,dest=${OUTPUT_DIR}/hss",
  ]

  cache-from = [
    "type=gha,scope=${CACHE_SCOPE}-hss",
  ]

  cache-to = [
    "type=gha,mode=max,scope=${CACHE_SCOPE}-hss",
  ]
}

target "buildroot" {
  inherits = ["_buildroot"]

  args = {
    BUILDROOT_DEFCONFIG = "microchip_mpfs_icicle_defconfig"
  }

  output = [
    "type=local,dest=${OUTPUT_DIR}/buildroot",
  ]

  cache-from = [
    "type=gha,scope=${CACHE_SCOPE}-buildroot",
  ]

  cache-to = [
    "type=gha,mode=max,scope=${CACHE_SCOPE}-buildroot",
  ]
}
