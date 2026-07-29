target "_buildroot" {
  context    = "."
  dockerfile = "scripts/Dockerfile.buildroot"
  target     = "export"
}

target "_blob" {
  context    = "."
  dockerfile = "scripts/Dockerfile.blob"
  target     = "export"
}
