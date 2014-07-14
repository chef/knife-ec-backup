$:.push File.join(File.dirname(__FILE__), '..', 'lib')
require 'simplecov'
SimpleCov.start do
   add_filter "/spec/"
   add_filter "/vendor/"
end
