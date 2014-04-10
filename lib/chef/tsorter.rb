require 'tsort'

class Chef
  class Tsorter

    include TSort

    def initialize(data)
      @data = data
    end

    def tsort_each_node(&block)
      @data.each_key(&block)
    end

    def tsort_each_child(node, &block)
      @data.fetch(node).each(&block)
    end
  end
end
