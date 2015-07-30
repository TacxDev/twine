# encoding: utf-8
require 'cgi'
require 'rexml/document'

module Twine
  module Formatters
    class Android < Abstract
      FORMAT_NAME = 'android'
      EXTENSION = '.xml'
      DEFAULT_FILE_NAME = 'strings.xml'
      LANG_CODES = Hash[
        'zh' => 'zh-Hans',
        'zh-rCN' => 'zh-Hans',
        'zh-rHK' => 'zh-Hant',
        'en-rGB' => 'en-UK',
        'in' => 'id',
        'nb' => 'no'
        # TODO: spanish
      ]
      DEFAULT_LANG_CODES = Hash[
        'zh-TW' => 'zh-Hant' # if we don't have a zh-TW translation, try zh-Hant before en
      ]

      def self.can_handle_directory?(path)
        Dir.entries(path).any? { |item| /^values.*$/.match(item) }
      end

      def default_file_name
        return DEFAULT_FILE_NAME
      end

      def determine_language_given_path(path)
        path_arr = path.split(File::SEPARATOR)
        path_arr.each do |segment|
          if segment == 'values'
            return @strings.language_codes[0]
          else
            match = /^values-(.*)$/.match(segment)
            if match
              lang = match[1]
              lang = LANG_CODES.fetch(lang, lang)
              lang.sub!('-r', '-')
              return lang
            end
          end
        end

        return
      end

      def read_file(path, lang)
        resources_regex = /<resources(?:[^>]*)>(.*)<\/resources>/m
        key_regex = /<(string|color) name="(\w+)">/
        comment_regex = /<!-- (.*) -->/
        value_regex = /<(string|color) name="(\w+)">([^<]*)<\/(string|color)>/
        ref_regex = /@\w+\/(\w+)/
        key = nil
        value = nil
        comment = nil

        File.open(path, 'r:UTF-8') do |f|
          content_match = resources_regex.match(f.read)
          if content_match
            content = content_match[1] 
            content = content.gsub(/\r\s*/," ")
            content = content.gsub(/\n\s*/," ")
            content = content.gsub(/\r\n\s*/," ")
            content = content.gsub(/>\s*</,">\n<")
            for item in content.scan(value_regex)
              key = item[1]
              value = item[2]
              ref_match = ref_regex.match(value)
              if ref_match
                ref = ref_match[1]
                if @strings.strings_map.include?(ref)
                  value = @strings.strings_map[ref].translations[lang]
                else
                  value = ""
                end
              else
                value = CGI.unescapeHTML(value)
                value.gsub!('\\\'', '\'')
                value.gsub!('\\"', '"')
                value = iosify_substitutions(value)
                value.gsub!(/(\\u0020)*|(\\u0020)*\z/) { |spaces| ' ' * (spaces.length / 6) }
              end

              set_translation_for_key(key, lang, value)
              if comment and comment.length > 0 and !comment.start_with?("SECTION:")
                set_comment_for_key(key, comment)
              end
              comment = nil
            end
          end
        end
      end

      def write_file(path, lang)
        default_lang = nil
        if DEFAULT_LANG_CODES.has_key?(lang)
          default_lang = DEFAULT_LANG_CODES[lang]
        end
        File.open(path, 'w:UTF-8') do |f|
          f.puts "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- Android Strings File -->\n<!-- Generated by Twine #{Twine::VERSION} -->\n<!-- Language: #{lang} -->"
          f.write '<resources>'
          @strings.sections.each do |section|
            printed_section = false
            section.rows.each do |row|
              if row.matches_tags?(@options[:tags], @options[:untagged])
                if !printed_section
                  f.puts ''
                  if section.name && section.name.length > 0
                    section_name = section.name.gsub('--', '—')
                    f.puts "\t<!-- SECTION: #{section_name} -->"
                  end
                  printed_section = true
                end

                key = row.key

                value = row.translated_string_for_lang(lang, default_lang)
                if !value && @options[:include_untranslated]
                  value = row.translated_string_for_lang(@strings.language_codes[0])
                end

                if value # if values is nil, there was no appropriate translation, so let Android handle the defaulting
                  value = String.new(value) # use a copy to prevent modifying the original

                  # Android enforces the following rules on the values
                  #  1) apostrophes and quotes must be escaped with a backslash
                  value.gsub!('\'', '\\\\\'')
                  value.gsub!('"', '\\\\"')
                  #  2) HTML escape the string
                  value = CGI.escapeHTML(value)
                  #  3) fix substitutions (e.g. %s/%@)
                  value = androidify_substitutions(value)
                  #  4) replace beginning and end spaces with \0020. Otherwise Android strips them.
                  value.gsub!(/\A *| *\z/) { |spaces| '\u0020' * spaces.length }

                  comment = row.comment
                  if comment
                    comment = comment.gsub('--', '—')
                  end

                  if comment && comment.length > 0
                    f.puts "\t<!-- #{comment} -->\n"
                  end
                  f.puts "\t<string name=\"#{key}\">#{value}</string>"
                end
              end
            end
          end

          f.puts '</resources>'
        end
      end
    end
  end
end
