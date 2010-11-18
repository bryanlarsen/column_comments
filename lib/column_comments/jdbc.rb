# we do not support table comments, just column comments.

module ActiveRecord::ConnectionAdapters
  class JdbcAdapter
    # Add an optional :comment to the options passed to change_column
    alias column_comments_add_column_options! add_column_options!
    def add_column_options!(sql, options) #:nodoc:
      column_comments_add_column_options!(sql, options)
      sql << " COMMENT #{quote(options[:comment][0..254])}" if options[:comment]
      #STDERR << "Column with options: #{sql}\n"
      sql
    end
  end
end
