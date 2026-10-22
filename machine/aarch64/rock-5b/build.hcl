variable "OUTPUT_DIR" {
  default = "components"
}

variable "CACHE_SCOPE" {
  default = "aarch64-rock-5b"
}

variable "BUILD_REVISION" {
  default = "1"
}

group "release-components" {
  targets = ["buildroot"]
}

target "buildroot" {
  inherits = ["_buildroot"]

  args = {
    BUILDROOT_REF              = "313414b92c2501a2bc123ffa1b6383dca464de05"
    BUILDROOT_DEFCONFIG        = "rock5b_defconfig"
    BUILDROOT_EXTERNAL_PATHS   = "machine/aarch64/rock-5b/buildroot-external"
    BUILDROOT_CONFIG_FRAGMENTS = "configs/rock5b_qemu.config"
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
