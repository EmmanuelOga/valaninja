module Ninja
  class Config < Struct.new(:base_path, :src_glob, :out_path, :vapi_paths, :vala_package_names, :binary_name)
    def initialize
      super; yield self
    end

    def binary_name=(name)
      super File.join(out_path, name)
    end

    def vala_package_params
      vala_package_names.map { |name| "--pkg #{name}" }.join(" ")
    end

    def vapi_paths
      @vapi_paths ||= {}
    end

    def objects
      @objects ||= []
    end

    def base_src_path
      src_glob.split("/").first
    end

    def each_path
      Dir[src_glob].each { |path| yield Ninja::Path.new(File.expand_path(path), self) }
    end

    def vapi_params(inpath)
      vapi_paths.reject { |k, v| k == inpath }.map { |_, path| "--use-fast-vapi=#{path}" }.join(" $\n#{' '*18}")
    end

    def pkg_config(what)
      vala_package_names.map { |pkg| `pkg-config --#{what} #{pkg}`.chomp }.join(" ")
    end
  end

  class Path < Struct.new(:path, :conf)
    require 'pathname'
    private :path=, :conf=

    def np(_path)
      self.class.new _path, conf
    end

    def pn(_path = path)
      Pathname.new(_path)
    end

    def relative_to_out_path
      np pn(conf.out_path).join(pn.relative_path_from(pn(conf.base_path)))
    end

    # rename the file to a new one with the given extension.
    def with_extension(new_ext)
      basepath, name = pn.split
      np pn(basepath).join("#{File.basename(name, File.extname(name))}.#{new_ext}")
    end

    def underscore
      word = path.to_s
      word.gsub!(/[\/.]/, "_")
      word.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
      word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
      word.tr!("-", "_")
      word.downcase!
      word.squeeze!("_")
      word
    end

    def to_s
      pn.absolute? ? pn.relative_path_from(pn(conf.base_path)).to_s : pn.to_s
    end
  end

  class Buffer
    require 'stringio'

    def buffers
      @buffer ||= Hash.new { |h,k| h[k] = StringIO.new }
    end
    private :buffers

    def section(section)
      block_given? ? yield(buffers[section]) : buffers[section].tap(&:rewind).read
    end
  end
end

module Ninja
  class Build < Struct.new(:conf)
    def banner(out, msg)
      msg.split("\n").each { |part| out << part.strip.chomp << "\n" }
    end

    def configure!(outfile)
      buffer = Buffer.new

      buffer.section(:header) do |out|
        out.puts "# Generated #{Time.now}"
        banner(out, %q{
          # __     __    _         _   _ _        _       _
          # \ \   / /_ _| | __ _  | \ | (_)_ __  (_) __ _| |
          #  \ \ / / _` | |/ _` | |  \| | | '_ \ | |/ _` | |
          #   \ V / (_| | | (_| |_| |\  | | | | || | (_| |_|
          #    \_/ \__,_|_|\__,_(_)_| \_|_|_| |_|/ |\__,_(_)
          #                                    |__/
        })
      end

      buffer.section(:vapis) do |out|
        banner(out, %q{
          # __     __          _
          # \ \   / /_ _ _ __ (_)___
          #  \ \ / / _` | '_ \| / __|
          #   \ V / (_| | |_) | \__ \
          #    \_/ \__,_| .__/|_|___/
          #             |_|
        })

        out.puts "rule fastvapi"
        out.puts "  description = valac fast vapi generation"
        out.puts "  restat = true"
        out.puts "  command = valac --fast-vapi=$out $in\n\n"

        conf.each_path do |inpath|
          outpath = inpath.relative_to_out_path.with_extension("vapi")
          conf.vapi_paths[inpath] = outpath

          out.puts "build #{outpath}: fastvapi #{inpath}"
        end
      end

      buffer.section(:cfiles) do |out|
        banner(out, %q{
          #         _____ _ _
          #   ___  |  ___(_) | ___  ___
          #  / __| | |_  | | |/ _ \/ __|
          # | (__  |  _| | | |  __/\__ \
          #(_)___| |_|   |_|_|\___||___/
          #
        })

        conf.each_path do |inpath|
          outpath = inpath.relative_to_out_path.with_extension("c")

          out.puts "rule rule_#{outpath.underscore}"
          out.puts "  description = valac compilation to .c files"
          out.puts "  command = valac #{conf.vala_package_params} -C $in -d #{conf.out_path} $"
          out.puts "                  #{conf.vapi_params(inpath)}"
          out.puts "\nbuild #{outpath}: rule_#{outpath.underscore} #{inpath} | $"
          out.puts "#{' '*18}#{conf.vapi_paths.values.join(" $\n#{' '*18}").strip}"
          out.puts "# ---\n\n"
        end
      end

      buffer.section(:objects) do |out|
        banner(out, %q{
          #          _____ _ _
          #   ___   |  ___(_) | ___  ___
          #  / _ \  | |_  | | |/ _ \/ __|
          # | (_) | |  _| | | |  __/\__ \
          #(_)___/  |_|   |_|_|\___||___/
          #
        })

        out.puts "rule ccobj"
        out.puts "  description = cc binary object files"
        out.puts "  command = cc -MMD -MF $out.d -c #{conf.pkg_config(:cflags)} $in -o $out"
        out.puts "  depfile = $out.d\n\n"

        conf.each_path do |inpath|
          outpath = inpath.relative_to_out_path.with_extension("o")
          out.puts "build #{outpath}: ccobj #{inpath.relative_to_out_path.with_extension("c")}"
          conf.objects << outpath
        end
      end

      buffer.section(:binary) do |out|
        banner(out, %q{
          #  _     _       _            _   ____  _
          # | |   (_)_ __ | | _____  __| | | __ )(_)_ __   __ _ _ __ _   _
          # | |   | | '_ \| |/ / _ \/ _` | |  _ \| | '_ \ / _` | '__| | | |
          # | |___| | | | |   <  __/ (_| | | |_) | | | | | (_| | |  | |_| |
          # |_____|_|_| |_|_|\_\___|\__,_| |____/|_|_| |_|\__,_|_|   \__, |
          #                                                          |___/
        })

        out.puts "rule ccbin"
        out.puts "  description = cc main binary executable"
        out.puts "  command = cc #{conf.pkg_config(:libs)} $in -o $out\n\n"
        out.puts "build #{conf.binary_name}: ccbin #{conf.objects.join(" ")} | #{conf.objects.join(" ")}"
      end

      [:header, :vapis, :cfiles, :objects, :binary].each { |section| outfile << buffer.section(section) }
    end
  end
end
