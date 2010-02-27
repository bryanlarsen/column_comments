require "config/environment"

MODEL_DIR   = File.join(RAILS_ROOT, "app/models")
FIXTURE_DIR = File.join(RAILS_ROOT, "test/fixtures")

module AnnotateModels
  mattr_accessor :text
  @@text = ""
  
  PREFIX = "Schema as of "

  # Use the column information in an ActiveRecord class
  # to create a comment block containing a line for
  # each column. The line contains the column name,
  # the type (and length), and any optional attributes
  def self.get_schema_info(klass, header)
    info = ""
    klass.columns.each do |col|
      attrs = []
      attrs << "default(#{col.default})" if col.default
      attrs << "not null" unless col.null

      col_type = col.type.to_s
      col_type << "(#{col.limit})" if col.limit

      info << "#  #{col.name}"
      info << " " * (40 - col.name.length) + col_type
      info << " " * (20 - col_type.length) + attrs.join(", ") unless attrs.empty?
      info << "\n"
      unless col.comment.blank?
        info << format_comment("#    ", col.comment)
        info << "\n#\n"
      end
    end

    info << "#\n\n"
    @@text << (klass.to_s + "\n\n" + info)
    
    "# #{header}\n#\n" + info
  end
  
  def self.format_comment(line_prefix, comment)
    wrapped = word_wrap(comment, 70)
    wrapped.map{|line| line_prefix + line}.join
  end
  
  def self.word_wrap(text, line_width = 80)
    text.gsub(/\n/, "\n\n").gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip
  end

  # Add a schema block to a file. If the file already contains
  # a schema info block (a comment starting
  # with "Schema as of ..."), remove it first.

  def self.annotate_one_file(file_name, info_block)
    if File.exist?(file_name)
      content = File.read(file_name)

      # Remove old schema info
      block_position = content.index("# #{PREFIX}") || 0
      content.sub!(/^# #{PREFIX}.*?\n(#.*\n)*\n/, '')
      
      # Put in new schema info
      content.insert(block_position, info_block)
      
      # Write it back
      File.open(file_name, "w") { |f| f.puts content }
    end
  end
  
  # Given the name of an ActiveRecord class, create a schema
  # info block (basically a comment containing information
  # on the columns and their types) and put it at the front
  # of the model and fixture source files.

  def self.annotate(klass, header)
    info = get_schema_info(klass, header)
    
    model_file_name = File.join(MODEL_DIR, klass.name.underscore + ".rb")
    annotate_one_file(model_file_name, info)

    fixture_file_name = File.join(FIXTURE_DIR, klass.table_name + ".yml")
    annotate_one_file(fixture_file_name, info)
  end

  # Return a list of the model files to annotate. If we have 
  # command line arguments, they're assumed to be either
  # the underscore or CamelCase versions of model names.
  # Otherwise we take all the model files in the 
  # app/models directory.
  def self.get_model_names
    models = ARGV.dup
    models.shift
    
    if models.empty?
      Dir.chdir(MODEL_DIR) do 
        models = Dir["**/*.rb"]
      end
    end
    models
  end

  # We're passed a name of things that might be 
  # ActiveRecord models. If we can find the class, and
  # if its a subclass of ActiveRecord::Base,
  # then pass it to the associated block

  def self.do_annotations
    header = PREFIX + Time.now.to_s
    version = ActiveRecord::Migrator.current_version
    if version > 0
      header << " (schema version #{version})"
    end
    
    self.get_model_names.each do |m|
      class_name = m.sub(/\.rb$/,'').camelize
      klass = class_name.split('::').inject(Object){ |klass,part| klass.const_get(part) } rescue nil 
      if klass && klass < ActiveRecord::Base
        puts "Annotating #{class_name}"
        self.annotate(klass, header)
      else
        puts "Skipping #{class_name}"
      end
    end
    
    File.open(File.join(RAILS_ROOT, "db/schema.txt"), "w") { |file| file.write @@text }
  end
end
