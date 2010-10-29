module ActiveRecord::ConnectionAdapters
  # Add a @comment attribute to columns
  class Column
    attr_reader :comment
    alias column_comments_original_initialize initialize
    def initialize(name, default, sql_type = nil, null = true, comment = nil)
      column_comments_original_initialize(name, default, sql_type, null)
      @comment = comment
    end
  end
  
  class MysqlColumn < (defined?(JdbcColumn) ? JdbcColumn : Column) #:nodoc:
    def initialize(name, default, sql_type = nil, null = true, comment = nil)
      @original_default = default
      super
      @default = nil if missing_default_forged_as_empty_string?(default)
    end
  end
  
  # Sneak the comment in through the add_column_options! method when create_table is called with a block
  class ColumnDefinition < ColumnDefinition.superclass #:nodoc:
    attr_accessor :comment
    
    private
    
      alias column_comments_original_add_column_options! add_column_options!
      def add_column_options!(sql, options)
        column_comments_original_add_column_options!(sql, options.merge(:comment => comment))
      end
  end
  
  # Pass the comment through the TableDefinition
  class TableDefinition
    alias column_comments_original_column column
    def column(name, type, options = {})
      column_comments_original_column(name, type, options)
      column = self[name]
      column.comment = options[:comment]
      self
    end
  end
  
  # Get comments on each when querying for column structure
  class MysqlAdapter < (defined?(JdbcAdapter) ? JdbcAdapter : AbstractAdapter)
    def columns(table_name, name = nil)#:nodoc:
      sql = "SHOW FULL FIELDS FROM #{table_name}"
      columns = []
      execute(sql, name).each { |field| columns << MysqlColumn.new(field[0], field[5], field[1], field[3] == "YES", field[8]) }
      columns
    end
    
    # Add an optional :comment to the options passed to change_column
    alias column_comments_add_column_options! add_column_options!
    def add_column_options!(sql, options) #:nodoc:
      column_comments_add_column_options!(sql, options)
      sql << " COMMENT #{quote(options[:comment])}" if options[:comment]
      #STDERR << "Column with options: #{sql}\n"
      sql
    end
    
    # Make sure we don't lose the comment when changing the name
    def rename_column(table_name, column_name, new_column_name, options = {}) #:nodoc:
      column_info = select_one("SHOW FULL FIELDS FROM #{table_name} LIKE '#{column_name}'")
      current_type = column_info["Type"]
      options[:comment] ||= column_info["Comment"]
      sql = "ALTER TABLE #{table_name} CHANGE #{column_name} #{new_column_name} #{current_type}"
      sql << " COMMENT #{quote(options[:comment])}" unless options[:comment].blank?
      execute sql
    end
    
    # Allow column comments to be explicitly set
    #def column_comment(table_name, column_name, comment) #:nodoc:
    #  rename_column(table_name, column_name, column_name, :comment => comment)
    #end
    
    # Mass assignment of comments in the form of a hash.  Example:
    #   column_comments {
    #     :users => {:first_name => "User's given name", :last_name => "Family name"},
    #     :tags  => {:id => "Tag IDentifier"}}
    def column_comments(contents)
      contents.each_pair do |table, cols|
        cols.each_pair do |col, comment|
          column_comment(table, col, comment)
        end
      end
    end
  end
end

module ActiveRecord
  class Migration
    # Small hack to counter the hackish way in which the first argument of all
    # methods called on Base#connection via Migration#method_missing are munged.
    def self.column_comments(*args)
      ActiveRecord::Base.connection.column_comments(*args)
    end
  end
  
  class SchemaDumper
    private
      def table(table, stream)
        columns = @connection.columns(table)
        begin
          tbl = StringIO.new

          if @connection.respond_to?(:pk_and_sequence_for)
            pk, pk_seq = @connection.pk_and_sequence_for(table)
          end
          pk ||= 'id'

          tbl.print "  create_table #{table.inspect}"
          if columns.detect { |c| c.name == pk }
            if pk != 'id'
              tbl.print %Q(, :primary_key => "#{pk}")
            end
          else
            tbl.print ", :id => false"
          end
          tbl.print ", :force => true"
          tbl.puts " do |t|"

          columns.each do |column|
            raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" if @types[column.type].nil?
            next if column.name == pk
            tbl.print "    t.column #{column.name.inspect}, #{column.type.inspect}"
            tbl.print ", :limit => #{column.limit.inspect}" if column.limit != @types[column.type][:limit] 
            tbl.print ", :default => #{column.default.inspect}" if !column.default.nil?
            tbl.print ", :null => false" if !column.null
            tbl.print ", :comment => #{column.comment.inspect}" if !column.comment.nil?
            tbl.puts
          end

          tbl.puts "  end"
          tbl.puts
        
          indexes(table, tbl)

          tbl.rewind
          stream.print tbl.read
        rescue => e
          stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end
      
        stream
      end
  end
end
