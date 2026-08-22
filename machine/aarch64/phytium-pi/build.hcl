variable "OUTPUT_DIR" {
  default = "components"
}

variable "CACHE_SCOPE" {
  default = "aarch64-phytium-pi"
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
    BUILDROOT_URL              = "https://gitee.com/phytium_embedded/phytium-linux-buildroot.git"
    BUILDROOT_REF              = "phytium-linux-buildroot_v2.4"
    BUILDROOT_DEFCONFIG        = "phytium_defconfig"
    BUILDROOT_CONFIG_FRAGMENTS = "configs/phytiumpi_sdcard.config"
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
