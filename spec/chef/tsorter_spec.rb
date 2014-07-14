require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))
require 'chef/tsorter'

describe Chef::Tsorter do
  it "returns an array of topologically sorted keys from a hash" do
    h = {"a" => ["b", "c"], "b" => [], "c" => ["b"]}
    expect(Chef::Tsorter.new(h).tsort).to eq(["b", "c", "a"])
  end
end
