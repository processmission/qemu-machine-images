target "_buildroot" {
  context    = "."
  dockerfile = "scripts/Dockerfile.buildroot"
  target     = "export"
}
