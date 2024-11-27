require_relative 'test_case'
require_relative "../lib/ncbo_annotator/recognizers/mallet"
require 'json'
require 'redis'

class TestAnnotator < TestCase

  def self.before_suite
    @@redis = Annotator::Models::NcboAnnotator.new.redis
    db_size = @@redis.dbsize

    if db_size > 10_000
      puts "   This test cannot be run. You are probably pointing to the wrong redis backend. "
      return
    end

    mappings = @@redis.keys.select { |x| x["mappings:"] }

    if mappings.length > 0
      @@redis.del(mappings)
    end
    mapping_test_set
  end

  def self.after_suite
  end

  def _remove_term_redis_cache
    _remove_cache_instance(Annotator.settings.annotator_redis_prefix)
    _remove_cache_instance(Annotator.settings.annotator_redis_alt_prefix)
    @@redis.del(Annotator::Models::NcboAnnotator::REDIS_PREFIX_KEY)
  end

  def _remove_cache_instance(inst)
    @@redis.del(Annotator::Models::NcboAnnotator::DICTHOLDER.call(inst))
    key_storage = Annotator::Models::NcboAnnotator::KEY_STORAGE.call(inst)

    # remove all the stored keys
    class_keys = @@redis.lrange(key_storage, 0, Annotator::Models::NcboAnnotator::CHUNK_SIZE)

    while !class_keys.empty?
      @@redis.del(class_keys)
      @@redis.ltrim(key_storage, Annotator::Models::NcboAnnotator::CHUNK_SIZE + 1, -1) # Remove what we just deleted
      class_keys = @@redis.lrange(key_storage, 0, Annotator::Models::NcboAnnotator::CHUNK_SIZE) # Get next chunk
    end
  end

  def test_all_classes_in_cache
    class_pages = TestAnnotator.all_classes(AnnotatorUnit.ontologies)
    annotator = Annotator::Models::NcboAnnotator.new
    assert class_pages.length > 100, "No classes in system ???"
    cur_inst = annotator.redis_current_instance()
    dict_holder = Annotator::Models::NcboAnnotator::DICTHOLDER.call(cur_inst)

    class_pages.each do |cls|
      prefLabel = cls.prefLabel.upcase()
      resourceId = cls.id.to_s
      prefixedId = annotator.get_prefixed_id_from_value(cur_inst, prefLabel)

      if prefLabel.length > 2
        assert @@redis.exists?(prefixedId), "The entry: #{resourceId} (PrefLabel: #{prefLabel}, PrefixedId: #{prefixedId}) does not exist"
        assert @@redis.hexists(prefixedId, resourceId)
        assert @@redis.hexists(dict_holder, prefixedId)
        assert_equal @@redis.hget(dict_holder, prefixedId), prefLabel
        assert !@@redis.hget(prefixedId, resourceId).empty?
      else
        assert !@@redis.exists?(prefixedId)
      end
    end
  end

  def test_generate_dictionary_file
    start_timestamp = Time.now
    sleep(1)
    ontologies = AnnotatorUnit.ontologies.dup
    class_pages = TestAnnotator.all_classes(ontologies)
    assert class_pages.length > 100, "No classes in system ???"
    annotator = Annotator::Models::NcboAnnotator.new
    annotator.generate_dictionary_file
    assert File.exists?(Annotator.settings.mgrep_dictionary_file), "The dictionary file did not get created successfully"
    lines = File.readlines(Annotator.settings.mgrep_dictionary_file)
    cur_inst = annotator.redis_current_instance()

    class_pages.each do |cls|
      prefLabel = cls.prefLabel.upcase()

      if prefLabel.length > 2
        resourceId = cls.id.to_s
        prefixedId = annotator.get_prefixed_id_from_value(cur_inst, prefLabel)
        index = lines.select{ |e| e.strip().split("\t")[1] == prefLabel }
        assert index.length > 0, "The concept: #{resourceId} (PrefLabel: #{prefLabel}, PrefixedId: #{prefixedId}) was not found in the dictionary file"
      end
    end
    #make sure length term is > 2
    lines.each do |line|
      assert line.strip().split("\t")[1].length > 2
    end
    assert @@redis.exists?(Annotator::Models::NcboAnnotator::MGREP_DICTIONARY_REFRESH_TIMESTAMP)
    assert @@redis.exists?(Annotator::Models::NcboAnnotator::LAST_MGREP_RESTART_TIMESTAMP)
    refresh_timestamp = @@redis.get(Annotator::Models::NcboAnnotator::MGREP_DICTIONARY_REFRESH_TIMESTAMP)
    assert_operator refresh_timestamp, :>, start_timestamp
  end

  def test_mallet_recognizer
    skip "Skipping Mallet recognizer test because the core Java APIs are not present" unless (File.exists?($ncbo_annotator_project_bin + "mallet.jar"))

    count, acronyms, cogpo = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        ont_count: 1,
        submission_count: 1,
        process_submission: true,
        acronym: Annotator::Models::Recognizers::Mallet::COGPO_ACRONYM,
        name: "Cognitive Paradigm Ontology",
        acronym_suffix: "",
        file_path: "../../../../test/data/ontology_files/CogPO12142010.owl"
    })

    annotator = Annotator::Models::Recognizers::Mallet.new

    text = "Schizophrenia subjects demonstrate difficulties on tasks requiring saccadic inhibition, despite normal refixation saccade performance. Saccadic inhibition is ostensibly mediated via prefrontal cortex and associated cortical/subcortical circuitry. The current study tests hypotheses about the neural substrates of normal and abnormal saccadic performance among subjects with schizophrenia.Using functional magnetic resonance imaging, blood oxygenation level-dependent (BOLD) data were recorded while 13 normal and 14 schizophrenia subjects were engaged in refixation and antisaccade tasks.Schizophrenia subjects did not demonstrate the increased prefrontal cortex BOLD contrast during antisaccade performance that was apparent in the normal subjects. Schizophrenia subjects did, however, demonstrate normal BOLD contrast associated with refixation saccade performance in the frontal and supplementary eye fields, and posterior parietal cortex.Results from the current study support hypotheses of dysfunctional prefrontal cortex circuitry among schizophrenia subjects. Furthermore, this abnormality existed despite normal BOLD contrast observed during refixation saccade generation in the schizophrenia group."
    all_annotations = annotator.annotate(text)
    assert_equal(4, all_annotations.length)

    text = "Depression with cognitive impairment, so called depressive pseudodementia, is commonly mistaken for a neurodegenerative dementia. Using positron emission tomography (PET) derived measures of regional cerebral blood flow (rCBF) a cohort of 33 patients with major depression was studied. Ten patients displayed significant and reversible cognitive impairment. The patterns of rCBF of these patients were compared with a cohort of equally depressed non-cognitively impaired depressed patients. In the depressed cognitively impaired patients a profile of rCBF abnormalities was identified consisting of decreases in the left anterior medial prefrontal cortex and increases in the cerebellar vermis. These changes were additional to those seen in depression alone and are distinct from those described in neurodegenerative dementia. The cognitive impairment seen in a proportion of depressed patients would seem to be associated with dysfunction of neural systems distinct from those implicated in depression alone or the neurodegenerative dementias."
    all_annotations = annotator.annotate(text)
    assert_equal(2, all_annotations.length)
    #  all_annotations.each do |ann|
    #    cls = LinkedData::Models::Class.find(ann.annotatedClass.id).in(cogpo[0].submissions[0]).include(:prefLabel).first
    #    puts cls.prefLabel
    #  end

    # check that the number of hits returned by mallet equals to the number of annotations for all existing abstracts
    dir_path = $ncbo_annotator_project_bin + "CogPOTerms/Abstracts/*.txt"
    not_found_labels = []
    not_found_terms = []
    found_terms = []

    Dir.glob(dir_path).each do |f|
      text = File.open(f).read

      stdout = annotator.mallet_java_call(text)
      labels = stdout.split(" ")

      labels.each do |label|
        category, sub_category = annotator.parse_label(label)

        unless (not_found_terms.include?(sub_category) || found_terms.include?(sub_category))
          hit = annotator.search_query(sub_category)

          if hit.nil?
            not_found_terms << sub_category
          else
            found_terms << sub_category
          end
        end

        not_found_labels << label if (not_found_terms.include?(sub_category) && !not_found_labels.include?(label))
      end
    end
  end

  def test_annotate_non_ascii
    annotator = Annotator::Models::NcboAnnotator.new

    text_fr = "Le Web sémantique a pour objectif le partage de connaissances contenues dans des silos d'informations, appelés aussi bases de données. Les données contenues dans une base de données classique sont dites non structurées vis-à-vis d'autres bases de données s'il n'existe aucune grammaire commune entre elles. Comme c'est le cas pour le langage humain, la ontology structuration syntaxique et grammaticale permet la création de phrases, éléments complexes d'où peut émerger un sens compréhensible par d'autres personnes. Sans grammaire, il ne peut y avoir de dialogues entre les différentes bases de données, et sans dialogues, aucune connaissance pérenne due à des synergies cognitives ou des partages ne peut émerger. L'existence d'une grammaire commune entre bases de données est la condition de structuration des données, donc du dialogue et de la confrontation productive des données. La recommandation OWL 5, en tant que grammaire commune, permet d'une part la vérification des données par la confrontation, leur fiabilité, et d'autre part une augmentation du volume de l'information. Cela signifie que la confrontation des données, rendue possible par le langage OWL, permet la création de nouvelles données (par exemple, lorsque deux informations lacunaires appartenant chacune à deux bases de données séparées sont mises en relation et se révèlent être complémentaires, la donnée qui en résulte est à la fois plus sûre et ouvre la porte à des avancées ultérieures)."
    annotations = annotator.annotate(text_fr, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true,
        longest_only: false
    })

    assert_equal(2, annotations.length)

    positions = annotations[0].annotations
    assert_equal(78, positions[0][:from])
    assert_equal(80, positions[0][:to])
    assert_equal(811, positions[3][:from])
    assert_equal(813, positions[3][:to])

    positions = annotations[1].annotations
    assert_equal(354, positions[0][:from])
    assert_equal(361, positions[0][:to])
  end

  def test_annotate_longest_only
    text = "Ontology development and management of the initial research findings was limited to a basic set of terms and constructs. The ontology development was to be executed in stages, starting from the general concepts and working toward a more granular representation."
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true,
        longest_only: true
    })
    assert_equal(2, annotations.length)

    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true,
        longest_only: false
    })
    assert_equal(3, annotations.length)
  end

  def test_annotate
    ontologies = AnnotatorUnit.ontologies.dup
    class_page = TestAnnotator.all_classes(ontologies)
    class_page = class_page[0..150]
    text = []
    size = 0

    class_page.each do |cls|
      prefLabel = cls.prefLabel
      text << "#{prefLabel}"
      if prefLabel.length > 2
        size += 1
      end
    end
    text = text.join ", "

    texts = [text, text.upcase, text.downcase]
    texts.each do |text|
      annotator = Annotator::Models::NcboAnnotator.new
      annotations = annotator.annotate(text, {
          ontologies: [],
          semantic_types: [],
          filter_integers: true,
          expand_class_hierarchy: false,
          expand_hierarchy_levels: 0,
          expand_with_mappings: false,
          min_term_size: nil,
          whole_word_only: true,
          with_synonyms: true
      })
      direct = annotations
      assert_operator 0, :<, direct.length
      assert_operator size, :<, direct.length
      found = 0
      class_page.each do |cls|
        if cls.prefLabel.length > 2
          #TODO: This assertion may fail if the dictionary file on mgrep server does not contain the terms from the test ontologies
          assert_operator 0, :<, (direct.select { |x| x.annotatedClass.id.to_s == cls.id.to_s }).length, "expected to find #{cls.id}"
          found += 1
        end
      end
      assert_operator size, :<=, found
    end

    # test for a specific class annotation
    term_text = "Data Storage"
    text = "#{term_text} is needed"
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    assert_equal 1, annotations.length
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Storage", annotations.first.annotatedClass.id.to_s
    assert_equal 1, annotations.first.annotations.length
    assert_equal 1, annotations.first.annotations.first[:from]
    assert_equal term_text.length, annotations.first.annotations.first[:to]
    assert_equal term_text, text[annotations.first.annotations.first[:from] - 1, annotations.first.annotations.first[:to]]

    # check for a non-existent ontology
    non_existent_ont = ["DOESNOTEXIST"]
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: non_existent_ont,
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })
    assert_empty(annotations)

    # check for a specific term
    term_text = "Outcomes research"
    text = "When #{term_text} is obtained properly, a new research can begin."
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })
  end

  def test_annotate_semantic_types_hierarchy
    text = "Funding Resource"
    ontologies = ["http://data.bioontology.org/ontologies/BROTEST-0"]
    annotator = Annotator::Models::NcboAnnotator.new

    annotations = annotator.annotate(text, {
      ontologies: ontologies,
      semantic_types: ["T021"],
      use_semantic_types_hierarchy: false
    })

    assert_empty(annotations)

    annotations = annotator.annotate(text, {
        ontologies: ontologies,
        semantic_types: ["T021"],
        use_semantic_types_hierarchy: true
    })

    assert_equal(1, annotations.length)
  end

  def test_annotate_minsize_term
    ontologies = AnnotatorUnit.ontologies.dup
    class_page = TestAnnotator.all_classes(ontologies)
    class_page = class_page[0..150]
    text = []
    size = 0

    class_page.each do |cls|
      prefLabel = cls.prefLabel
      text << "#{prefLabel}"
      if prefLabel.length > 2
        size += 1
      end
    end
    text = text.join ", "

    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: true,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })
    direct = annotations

    assert_operator 0, :<, direct.length
    assert_operator size, :<, direct.length
    found = 0
    filter_out_next = []
    must_be_next = []
    class_page.each do |cls|
      if cls.prefLabel.length > 2
        #TODO: This assertion may fail if the dictionary file on mgrep server does not contain the terms from the test ontologies
        assert_operator 0, :<, (direct.select { |x| x.annotatedClass.id.to_s == cls.id.to_s }).length
        found += 1
        if cls.prefLabel.length < 10
          filter_out_next << cls
        else
          must_be_next << cls
        end
      end
    end
    assert found >= size

    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: true,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: 10,
        whole_word_only: true,
        with_synonyms: false
    })

    direct = annotations
    filter_out_next.each do |cls|
      assert_equal 0, (direct.select { |x| x.annotatedClass.id.to_s == cls.id.to_s }).length
    end
    must_be_next.each do |cls|
      assert_operator 0, :<, (direct.select { |x| x.annotatedClass.id.to_s == cls.id.to_s }).length
    end
    assert_operator 0, :<, must_be_next.length
    assert_operator 0, :<, filter_out_next.length
  end

  def test_annotate_stop_words
    ontologies = AnnotatorUnit.ontologies.dup
    text = "Aggregate Human Data, Resource deletion, chromosomal chromosomal mutation"
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })
    not_show = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
                "http://purl.obolibrary.org/obo/MCBCC_0000296#Deletion"]

    not_show.each do |cls|
      assert_operator 0, :<, (annotations.select { |x| x.annotatedClass.id.to_s == cls }).length
    end

    #annotation should not show up
    annotator = Annotator::Models::NcboAnnotator.new
    annotator.stop_words = ["resource", "deletion"]
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    not_show.each do |cls|
      assert_equal 0, (annotations.select { |x| x.annotatedClass.id.to_s == cls }).length
    end

    #empty array must annotate all
    annotator = Annotator::Models::NcboAnnotator.new
    annotator.stop_words = []
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    not_show.each do |cls|
      assert_operator 0, :<, (annotations.select { |x| x.annotatedClass.id.to_s == cls }).length
    end
  end

  def test_annotate_hierarchy
    ontologies = AnnotatorUnit.ontologies.dup
    text = "Aggregate Human Data Aggregate Human Data"
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text)
    assert_equal 1, annotations.length
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data", annotations.first.annotatedClass.id.to_s
    assert_equal "BROTEST-0", annotations.first.annotatedClass.submission.ontology.acronym
    assert_equal 2, annotations.first.annotations.length
    assert_equal 1, annotations.first.annotations.first[:from]
    assert_equal "Aggregate Human Data".length, annotations.first.annotations.first[:to]
    assert_equal 2 + ("Aggregate Human Data".length), annotations.first.annotations[1][:from]
    assert_equal "Aggregate Human Data", text[annotations.first.annotations.first[:from]-1,annotations.first.annotations.first[:to]]
    assert_equal (1 + ("Aggregate Human Data".length)) + ("Aggregate Human Data".length), annotations.first.annotations[1][:to]
    assert_equal "Aggregate Human Data", text[annotations.first.annotations[1][:from]-1,annotations.first.annotations[1][:to]-1]
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: true,
        expand_hierarchy_levels: 1,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    assert_equal 1, annotations.length
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data", annotations.first.annotatedClass.id.to_s
    assert_equal "BROTEST-0", annotations.first.annotatedClass.submission.ontology.acronym
    assert_equal 2, annotations.first.annotations.length
    assert_equal 1, annotations.first.annotations.first[:from]
    assert_equal "Aggregate Human Data".length, annotations.first.annotations.first[:to]

    assert_equal 1, annotations.first.hierarchy.length
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Clinical_Care_Data", annotations.first.hierarchy.first.annotatedClass.id.to_s
    assert_equal 1, annotations.first.hierarchy.first.distance
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: true,
        expand_hierarchy_levels: 3,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    assert_equal 3, annotations.first.hierarchy.length
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Clinical_Care_Data", annotations.first.hierarchy.first.annotatedClass.id.to_s
    assert_equal 1, annotations.first.hierarchy.first.distance
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource", annotations.first.hierarchy[1].annotatedClass.id.to_s
    assert_equal 2, annotations.first.hierarchy[1].distance
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource", annotations.first.hierarchy[2].annotatedClass.id.to_s
    assert_equal 3, annotations.first.hierarchy[2].distance
  end

  def test_annotate_hierachy_terms_multiple
    ontologies = AnnotatorUnit.ontologies.dup
    text = "Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation"
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: true,
        expand_hierarchy_levels: 5,
        expand_with_mappings: false,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data", annotations[0].annotatedClass.id.to_s
    assert_equal 3, annotations[0].annotations.length
    assert_equal 4, annotations[0].hierarchy.length
    hhh = annotations[0].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    hhh.sort!

    assert_equal [
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Clinical_Care_Data",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"
    ].sort, hhh

    assert_equal "http://purl.obolibrary.org/obo/MCBCC_0000288#ChromosomalMutation", annotations[1].annotatedClass.id.to_s
    assert_equal 2, annotations[1].annotations.length
    hhh = annotations[1].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_equal ["http://purl.obolibrary.org/obo/MCBCC_0000287#GeneticVariation"], hhh

    assert_equal "http://purl.obolibrary.org/obo/MCBCC_0000289#ChromosomalDeletion", annotations[2].annotatedClass.id.to_s
    assert_equal 1, annotations[2].annotations.length
    hhh = annotations[2].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert hhh == ["http://purl.obolibrary.org/obo/MCBCC_0000287#GeneticVariation",
            "http://purl.obolibrary.org/obo/MCBCC_0000288#ChromosomalMutation"]

    assert_equal "http://purl.obolibrary.org/obo/MCBCC_0000296#Deletion", annotations[3].annotatedClass.id.to_s
    hhh = annotations[3].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_equal ["http://purl.obolibrary.org/obo/MCBCC_0000287#GeneticVariation",
     "http://purl.obolibrary.org/obo/MCBCC_0000295#GeneMutation"], hhh

    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource", annotations[4].annotatedClass.id.to_s
    hhh = annotations[4].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_equal ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource"], hhh

    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource", annotations[5].annotatedClass.id.to_s
    hhh = annotations[5].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_empty hhh

    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Federal_Funding_Resource", annotations[6].annotatedClass.id.to_s
    hhh = annotations[6].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_equal ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Funding_Resource"], hhh

    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Funding_Resource", annotations[7].annotatedClass.id.to_s
    hhh = annotations[7].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_equal ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource" ], hhh

    assert_equal "http://purl.obolibrary.org/obo/MCBCC_0000275#ReceptorAntagonists", annotations[8].annotatedClass.id.to_s
    hhh = annotations[8].hierarchy.sort {|x| x.distance }.map { |x| x.annotatedClass.id.to_s }
    assert_equal ["http://purl.obolibrary.org/obo/MCBCC_0000256#ChemicalsAndDrugs"], hhh

  end

  def self.mapping_test_set
    Goo.sparql_data_client.delete_graph(LinkedData::Models::MappingProcess.type_uri)
    terms_a = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
               "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data",
               "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource",
               "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"]
    onts_a = ["BROTEST-0","BROTEST-0","BROTEST-0","BROTEST-0"]
    terms_b = ["http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#La_mastication_de_produit",
               "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Article",
               "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Maux_de_rein",
               "http://purl.obolibrary.org/obo/MCBCC_0000344#PapillaryInvasiveDuctalTumor"]
    onts_b = ["ONTOMATEST-0","ONTOMATEST-0","ONTOMATEST-0", "MCCLTEST-0"]

    user_creator = LinkedData::Models::User.where.include(:username).page(1,100).first
    if user_creator.nil?
      u = LinkedData::Models::User.new(username: "tim",
                                       email: "tim@example.org",
                                       password: "password")
      u.save
      user_creator = LinkedData::Models::User.where.include(:username).page(1,100).first
    end
    process = LinkedData::Models::MappingProcess.new(
      :creator => user_creator, :name => "TEST Mapping Annotator")
    process.date = DateTime.now
    process.relation = RDF::URI.new("http://bogus.relation.com/predicate")
    process.save

    4.times do |i|
        classes = []
        class_id = terms_a[i]
        ont_acr = onts_a[i]
        sub = LinkedData::Models::Ontology.find(ont_acr).first.latest_submission
        sub.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                    .in(sub)
                                    .first
        classes << c
        class_id = terms_b[i]
        ont_acr = onts_b[i]
        sub = LinkedData::Models::Ontology.find(ont_acr).first.latest_submission
        sub.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                    .in(sub)
                                    .first
        classes << c
        LinkedData::Mappings.create_rest_mapping(classes,process)
    end
  end

  def test_annotate_with_mappings
    text = "Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation"
    annotator = Annotator::Models::NcboAnnotator.new
    annotations = annotator.annotate(text, {
        ontologies: [],
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: true,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    step_in_here = 0
    annotations.each do |ann|
      if ann.annotatedClass.id.to_s ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data"
        step_in_here += 1
        assert ann.mappings.length == 1
        assert ann.mappings.first[:annotatedClass].id.to_s ==
            "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Article"
        assert ann.mappings.first[:annotatedClass].submission.ontology.id.to_s ==
          "http://data.bioontology.org/ontologies/ONTOMATEST-0"
      elsif ann.annotatedClass.id.to_s ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"
        step_in_here += 1
        assert ann.mappings.length == 2
        ann.mappings.each do |map|
          if map[:annotatedClass].id.to_s =="http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Maux_de_rein"
            assert map[:annotatedClass].submission.ontology.id.to_s["ONTOMATEST-0"]
          elsif map[:annotatedClass].id.to_s == "http://purl.obolibrary.org/obo/MCBCC_0000344#PapillaryInvasiveDuctalTumor"
            assert map[:annotatedClass].submission.ontology.id.to_s["MCCLTEST-0"]
          else
            assert 1==0
          end
        end
      else
        ann.mappings.length == 0
      end
    end
    assert step_in_here == 2

    #filtering on ontologies
    ontologies = ["http://data.bioontology.org/ontologies/ONTOMATEST-0",
                 "http://data.bioontology.org/ontologies/BROTEST-0"]
    annotations = annotator.annotate(text, {
        ontologies: ontologies,
        semantic_types: [],
        filter_integers: false,
        expand_class_hierarchy: false,
        expand_hierarchy_levels: 0,
        expand_with_mappings: true,
        min_term_size: nil,
        whole_word_only: true,
        with_synonyms: true
    })

    step_in_here = 0
    annotations.each do |ann|
      if ann.annotatedClass.id.to_s ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data"
        step_in_here += 1
        assert ann.mappings.length == 1
        assert ann.mappings.first[:annotatedClass].id.to_s ==
          "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Article"
        assert ann.mappings.first[:annotatedClass].submission.ontology.id.to_s ==
          "http://data.bioontology.org/ontologies/ONTOMATEST-0"
      elsif ann.annotatedClass.id.to_s ==
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"
        step_in_here += 1
        assert ann.mappings.length == 1
        ann.mappings.each do |map|
          if map[:annotatedClass].id.to_s ==
                "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Maux_de_rein"
            assert map[:annotatedClass].submission.ontology.id.to_s["ONTOMATEST-0"]
          else
            assert 1==0
          end
        end
      end
    end
    assert step_in_here == 2
  end

  def self.all_classes(ontologies)
    classes = []
    ontologies.each do |ontology|
      last = ontology.latest_submission
      page = 1
      size = 500
      paging = LinkedData::Models::Class.in(last)
                            .include(:prefLabel, :synonym, :definition)
                            .page(page, size)
      begin
        page_classes = paging.page(page,size).all
        page = page_classes.next? ? page + 1 : nil
        classes += page_classes
      end while !page.nil?
    end
    return classes
  end

end
