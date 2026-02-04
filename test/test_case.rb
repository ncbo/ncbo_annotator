if ENV['COVERAGE'] == 'true' || ENV['CI'] == 'true'
  require 'simplecov'
  require 'simplecov-cobertura'
  # https://github.com/codecov/ruby-standard-2
  # Generate HTML and Cobertura reports which can be consumed by codecov uploader
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ])
  SimpleCov.start do
    add_filter '/test/'
    add_filter 'app.rb'
    add_filter 'init.rb'
    add_filter '/config/'
  end
end

require_relative '../lib/ncbo_annotator'
require_relative '../config/config'

# Check to make sure you want to run if not pointed at localhost
safe_host = Regexp.new(/localhost|-ut|ncbo-dev*|ncbo-unittest*/)
unless LinkedData.settings.goo_host.match(safe_host) && LinkedData.settings.search_server_url.match(safe_host) && Annotator.settings.annotator_redis_host.match(safe_host)
  print '\n\n================================== WARNING ==================================\n'
  print '** TESTS CAN BE DESTRUCTIVE -- YOU ARE POINTING TO A POTENTIAL PRODUCTION/STAGE SERVER **\n'
  print 'Servers:\n'
  print "triplestore -- #{LinkedData.settings.goo_host}\n"
  print "search -- #{LinkedData.settings.search_server_url}\n"
  print "redis annotator -- #{Annotator.settings.annotator_redis_host}:#{Annotator.settings.annotator_redis_port}\n"
  print "Type 'y' to continue: "
  $stdout.flush
  confirm = $stdin.gets
  abort('Canceling tests...\n\n') unless confirm.strip == 'y'
  print 'Running tests...'
  $stdout.flush
end

require 'minitest/autorun'

class AnnotatorUnit
  class << self
    attr_accessor :ontologies
  end

  def self.setup_once
    return if @setup_done

    @setup_done = true
    # code to run before the very first test
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    self.ontologies = LinkedData::SampleData::Ontology.sample_owl_ontologies(process_submission: true)
    LinkedData::SampleData::Ontology.load_semantic_types_ontology(process_submission: true)
    annotator = Annotator::Models::NcboAnnotator.new
    annotator.init_redis_for_tests
    annotator.create_term_cache_from_ontologies(ontologies, true)
    annotator.redis_switch_instance

    Minitest::Runnable.runnables.each do |suite|
      suite.before_suite if suite.respond_to?(:before_suite)
    end
  end
end

module AnnotatorTestSetup
  def before_setup
    AnnotatorUnit.setup_once
    super
  end
end

Minitest::Test.prepend(AnnotatorTestSetup)

Minitest.after_run do
  Minitest::Runnable.runnables.each do |suite|
    suite.after_suite if suite.respond_to?(:after_suite)
  end

  # code to run after the very last test
  LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
end

##
# Base test class. Put shared test methods or setup here.
class TestCase < Minitest::Test
end
