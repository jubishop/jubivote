require 'colorize'

require_relative 'env'

module RSpec
  class Goldens
    def self.verify(page, filename, **options)
      return if github_actions?

      expect(page).to(have_googlefonts)

      page.driver.save_screenshot(golden_file(filename), **options)
      new_base64 = Base64.encode64(File.read(golden_file(filename)))

      unless File.exist?(base64_file(filename))
        File.write(base64_file(filename), new_base64)
        system("open #{golden_file(filename)}")
        return
      end

      golden_base64 = File.read(base64_file(filename))
      return if golden_base64 == new_base64

      warn("Golden match failed for: #{filename}".red)
      File.write(base64_file(filename), new_base64)
      system("open #{golden_file(filename)}")
      return unless ENV.fetch('FAIL_ON_GOLDEN', false)

      raise RSpec::Expectations::ExpectationNotMetError,
            "#{filename} does not match"
    end

    def self.view(page, filename, **options)
      expect(page).to(have_googlefonts)
      tmp_file = File.join(ENV.fetch('TMPDIR', '/tmp'), "#{filename}.png")
      page.driver.save_screenshot(tmp_file, **options)
      system("open #{tmp_file}")
    end

    class << self
      include Capybara::RSpecMatchers
      include RSpec::Env
      include RSpec::Matchers

      private

      def write_golden(page, filename, **options)
        File.write(base64_file(filename),
                   page.driver.render_base64(:png, **options))
      end

      def golden_file(filename)
        return File.join('spec/goldens', "#{filename}.png")
      end

      def base64_file(filename)
        return File.join('spec/goldens/base64', filename)
      end
    end
  end
end
