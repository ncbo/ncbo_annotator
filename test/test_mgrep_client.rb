require "minitest/autorun"

require_relative "../lib/ncbo_annotator"
require_relative "../config/config.test"

class TestMgrepClient < Minitest::Test

  def test_mgrep
    client = Annotator::Mgrep::Client.new(Annotator.settings.mgrep_host, Annotator.settings.mgrep_port, Annotator.settings.mgrep_alt_host, Annotator.settings.mgrep_alt_port)
    annotations = client.annotate("Cough LUNG Chest XXXXXZZZZZ", true)
    known = ["COUGH", "LUNG", "CHEST"]
    annotations.each do |ann|
      assert(known.include? ann.value)
    end
    client.close()
  end

  def test_mgrep_multiple_calls
    client = Annotator::Mgrep::Client.new(Annotator.settings.mgrep_host, Annotator.settings.mgrep_port, Annotator.settings.mgrep_alt_host, Annotator.settings.mgrep_alt_port)
    known = ["COUGH", "LUNG", "CHEST"]
    10.times do
      annotations = client.annotate("Cough LUNG Chest", true)
      annotations.each do |ann|
        assert(known.include? ann.value)
      end
    end
    client.close()
  end

  def test_mgrep_long_text
    long_abstract = <<eos
Ginsenosides chemistry, biosynthesis, analysis, and potential health effects." "Ginsenosides are a special group of triterpenoid saponins that can be classified into two groups by the skeleton of their aglycones, namely dammarane- and oleanane-type. Ginsenosides are found nearly exclusively in Panax species (ginseng) and up to now more than 150 naturally occurring ginsenosides have been isolated from roots, leaves/stems, fruits, and/or flower heads of ginseng. Ginsenosides have been the target of a lot of research as they are believed to be the main active principles behind the claims of ginsengs efficacy. The potential health effects of ginsenosides that are discussed in this chapter include anticarcinogenic, immunomodulatory, anti-inflammatory, antiallergic, antiatherosclerotic, antihypertensive, and antidiabetic effects as well as antistress activity and effects on the central nervous system. Ginsensoides can be metabolized in the stomach (acid hydrolysis) and in the gastrointestinal tract (bacterial hydrolysis) or transformed to other ginsenosides by drying and steaming of ginseng to more bioavailable and bioactive ginsenosides. The metabolization and transformation of intact ginsenosides, which seems to play an important role for their potential health effects, are discussed. Qualitative and quantitative analytical techniques for the analysis of ginsenosides are important in relation to quality control of ginseng products and plant material and for the determination of the effects of processing of plant material as well as for the determination of the metabolism and bioavailability of ginsenosides. Analytical techniques for the analysis of ginsenosides that are described in this chapter are thin-layer chromatography (TLC), high-performance liquid chromatography (HPLC) combined with various detectors, gas chromatography (GC), colorimetry, enzyme immunoassays (EIA), capillary electrophoresis (CE), nuclear magnetic resonance (NMR) spectroscopy, and spectrophotometric methods.
eos
    client = Annotator::Mgrep::Client.new(Annotator.settings.mgrep_host, Annotator.settings.mgrep_port, Annotator.settings.mgrep_alt_host, Annotator.settings.mgrep_alt_port)
    annotations = client.annotate(long_abstract, true)
    annotations.filter_min_size(5)
    annotations.each do |ann|
      assert (ann.value.length >= 5)
    end
    client.close()
  end

  def test_long_vs_short_word_matching
    client = Annotator::Mgrep::Client.new(Annotator.settings.mgrep_host, Annotator.settings.mgrep_port, Annotator.settings.mgrep_alt_host, Annotator.settings.mgrep_alt_port)
    annotations = client.annotate("Legal occupations Officer of the court", true)
    known = ["LEGAL OCCUPATIONS", "OFFICER OF THE COURT"]
    annotations.each do |ann|
      assert (known.include? ann.value)
    end
    annotations = client.annotate("Legal occupations Officer of the court", false)
    known = ["LEGAL OCCUPATIONS", "OFFICER OF THE COURT","OCCUPATIONS", "LEGAL", "COURT", "OF"]
    annotations.each do |ann|
      assert (known.include? ann.value)
    end
    client.close()
  end
end
