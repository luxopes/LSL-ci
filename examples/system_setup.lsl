# This is a normal LSL program and changes the host package state when run.
load system

packages = ["git", "curl", "ca-certificates"]
for package in packages:
    backend = system.install(package)
    print package, "installed by", backend
end
