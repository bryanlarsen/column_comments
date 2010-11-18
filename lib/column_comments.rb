
# FIXME: this test will fail if the load order is different or if the
# user has loaded more than one adapter.   We should really ask
# ActiveRecord what the adapter is
if defined?(ActiveRecord::ConnectionAdapters::JdbcAdapter)
  require 'column_comments/jdbc'
else
  require 'column_comments/mysql'
end
