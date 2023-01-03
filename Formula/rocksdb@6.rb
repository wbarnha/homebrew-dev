class RocksdbAT6 < Formula
  desc "Embeddable, persistent key-value store for fast storage"
  homepage "https://rocksdb.org/"
  url "https://github.com/facebook/rocksdb/archive/v6.11.4.tar.gz"
  sha256 "6793ef000a933af4a834b59b0cd45d3a03a3aac452a68ae669fb916ddd270532"
  license "GPL-2.0"

  bottle do
    cellar :any
    sha256 "0365931b288f5eba6cebab4cc74e00735cd9a32431a944ccacdc22af3f30523d" => :big_sur
    sha256 "e480342b56120c038d7d29de482eea256f3d4b4b173701a37fdf9afddf92b9a9" => :catalina
    sha256 "230c7bb4164b9a819da6b8118252c650e6b71a04769bfd242d3e561ab9361cc2" => :mojave
    sha256 "c08fc8d6ad16f159fe8a2dccf118752e730fad45840c95ed2cf34cf875474c66" => :high_sierra
  end

  keg_only :versioned_formula

  depends_on "cmake" => :build
  depends_on "gflags"
  depends_on "lz4"
  depends_on "snappy"
  depends_on "zstd"

  uses_from_macos "bzip2"
  uses_from_macos "zlib"

  def install
    ENV.cxx11
    base_args = std_cmake_args + %W[
      -DPORTABLE=ON
      -DUSE_RTTI=ON
      -DWITH_BENCHMARK_TOOLS=OFF
      -DWITH_BZ2=ON
      -DWITH_LZ4=ON
      -DWITH_SNAPPY=ON
      -DWITH_ZLIB=ON
      -DWITH_ZSTD=ON
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath,#{rpath}
    ]

    # build rocksdb_lite
    lite_args = base_args + %w[
      -DROCKSDB_LITE=ON
      -DARTIFACT_SUFFIX=_lite
      -DWITH_CORE_TOOLS=OFF
      -DWITH_TOOLS=OFF
    ]
    mkdir "build_lite" do
      system "cmake", "..", *lite_args
      system "make", "install"
    end
    p = lib/"cmake/rocksdb/RocksDB"
    ["Targets.cmake", "Targets-release.cmake"].each do |s|
      File.rename "#{p}#{s}", "#{p}_Lite#{s}"
    end

    # build regular rocksdb
    mkdir "build" do
      system "cmake", "..", *base_args
      system "make", "install"

      cd "tools" do
        bin.install "sst_dump" => "rocksdb_sst_dump"
        bin.install "db_sanity_test" => "rocksdb_sanity_test"
        bin.install "write_stress" => "rocksdb_write_stress"
        bin.install "ldb" => "rocksdb_ldb"
        bin.install "db_repl_stress" => "rocksdb_repl_stress"
        bin.install "rocksdb_dump"
        bin.install "rocksdb_undump"
      end
      bin.install "db_stress_tool/db_stress" => "rocksdb_stress"
    end

    # build pkgconfig file
    system "make", "gen-pc", "PREFIX=#{prefix}"
    (lib/"pkgconfig").install "rocksdb.pc"
  end

  test do
    (testpath/"test.cpp").write <<~EOS
      #include <assert.h>
      #include <rocksdb/options.h>
      #include <rocksdb/memtablerep.h>
      using namespace rocksdb;
      int main() {
        Options options;
        return 0;
      }
    EOS

    extra_args = []
    if OS.mac?
      extra_args << "-stdlib=libc++"
      extra_args << "-lstdc++"
    end
    system ENV.cxx, "test.cpp", "-o", "db_test", "-v",
                                "-std=c++11",
                                *extra_args,
                                "-lz", "-lbz2",
                                "-L#{lib}", "-lrocksdb",
                                "-L#{Formula["snappy"].opt_lib}", "-lsnappy",
                                "-L#{Formula["lz4"].opt_lib}", "-llz4",
                                "-L#{Formula["zstd"].opt_lib}", "-lzstd",
                                "-I#{include}"
    system "./db_test"
    system ENV.cxx, "test.cpp", "-o", "db_test_lite", "-v",
                                "-std=c++11",
                                *extra_args,
                                "-lz", "-lbz2",
                                "-L#{lib}", "-lrocksdb_lite",
                                "-DROCKSDB_LITE=1",
                                "-L#{Formula["snappy"].opt_lib}", "-lsnappy",
                                "-L#{Formula["lz4"].opt_lib}", "-llz4",
                                "-L#{Formula["zstd"].opt_lib}", "-lzstd",
                                "-I#{include}"
    system "./db_test_lite"

    assert_match "sst_dump --file=", shell_output("#{bin}/rocksdb_sst_dump --help 2>&1")
    assert_match "rocksdb_sanity_test <path>", shell_output("#{bin}/rocksdb_sanity_test --help 2>&1", 1)
    assert_match "rocksdb_stress [OPTIONS]...", shell_output("#{bin}/rocksdb_stress --help 2>&1", 1)
    assert_match "rocksdb_write_stress [OPTIONS]...", shell_output("#{bin}/rocksdb_write_stress --help 2>&1", 1)
    assert_match "ldb - RocksDB Tool", shell_output("#{bin}/rocksdb_ldb --help 2>&1")
    assert_match "rocksdb_repl_stress:", shell_output("#{bin}/rocksdb_repl_stress --help 2>&1", 1)
    assert_match "rocksdb_dump:", shell_output("#{bin}/rocksdb_dump --help 2>&1", 1)
    assert_match "rocksdb_undump:", shell_output("#{bin}/rocksdb_undump --help 2>&1", 1)

    db = testpath / "db"
    %w[no snappy zlib bzip2 lz4 zstd].each_with_index do |comp, idx|
      key = "key-#{idx}"
      value = "value-#{idx}"

      put_cmd = "#{bin}/rocksdb_ldb put --db=#{db} --create_if_missing --compression_type=#{comp} #{key} #{value}"
      assert_equal "OK", shell_output(put_cmd).chomp

      get_cmd = "#{bin}/rocksdb_ldb get --db=#{db} #{key}"
      assert_equal value, shell_output(get_cmd).chomp
    end
  end
end
