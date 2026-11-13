# Homebrew cask template. scripts/release.sh fills in the placeholders (with GITHUB_REPO set)
# and writes the result to build/ip-calc.rb, which goes to Casks/ip-calc.rb in the tap repository.
cask "ip-calc" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/__GITHUB_REPO__/releases/download/v#{version}/IP-Calc-#{version}.zip"
  name "IP Calc"
  desc "Offline IPv4/IPv6 subnet calculator in a Spotlight-style panel"
  homepage "https://github.com/__GITHUB_REPO__"

  depends_on macos: ">= :tahoe"

  app "IP Calc.app"

  uninstall quit: "sk.backbone.ipcalc"

  zap trash: "~/Library/Containers/sk.backbone.ipcalc"
end
