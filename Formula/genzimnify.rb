class Genzimnify < Formula
  desc "Native, Python-free programming language with Gen Z syntax"
  homepage "https://github.com/Obliv1onis/Genzimnify"
  head "https://github.com/Obliv1onis/Genzimnify.git", branch: "master"
  license "MIT"

  depends_on arch: :arm64
  depends_on "nim" => :build
  depends_on "cmake" => :build

  resource "raylib" do
    url "https://github.com/raysan5/raylib/archive/refs/tags/5.5.tar.gz"
    sha256 "aea98ecf5bc5c5e0b789a76de0083a21a70457050ea4cc2aec7566935f5e258e"
  end

  def install
    resource("raylib").stage do
      system "cmake", "-S", ".", "-B", "build", "-DCMAKE_BUILD_TYPE=Release",
                      "-DBUILD_SHARED_LIBS=ON", "-DBUILD_EXAMPLES=OFF",
                      "-DBUILD_GAMES=OFF", "-DCMAKE_INSTALL_PREFIX=#{prefix}"
      system "cmake", "--build", "build", "--parallel"
      system "cmake", "--install", "build"
    end
    system "nim", "c", "-d:release", "--out:#{bin}/gzim", "src/gzim.nim"
    system "nim", "c", "-d:release", "--out:#{bin}/gzim-lsp", "src/gzimlsp.nim"
  end

  test do
    assert_match "native Nim (Python-free)", shell_output("#{bin}/gzim doctor")
    (testpath/"hello.gzim").write <<~EOS
      yap("no cap")
    EOS
    assert_equal "no cap\n", shell_output("#{bin}/gzim hello.gzim")
    assert_match "raylib 5.5", shell_output("#{bin}/gzim eval 'pull up rizzgame as rg; yap(call up rg.get_backend() yo)'")
  end
end
