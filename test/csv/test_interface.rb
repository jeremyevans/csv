# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "helper"
require "tempfile"

class TestCSVInterface < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @tempfile = Tempfile.new(%w"temp .csv")
    @tempfile.close
    @path = @tempfile.path

    File.open(@path, "wb") do |file|
      file << "1\t2\t3\r\n"
      file << "4\t5\r\n"
    end

    @expected = [%w{1 2 3}, %w{4 5}]
  end

  def teardown
    @tempfile.close(true)
    super
  end

  ### Test Read Interface ###

  def test_foreach
    CSV.foreach(@path, col_sep: "\t", row_sep: "\r\n") do |row|
      assert_equal(@expected.shift, row)
    end
  end

  def test_foreach_enum
    CSV.foreach(@path, col_sep: "\t", row_sep: "\r\n").zip(@expected) do |row, exp|
      assert_equal(exp, row)
    end
  end

  def test_open_and_close
    csv = CSV.open(@path, "r+", col_sep: "\t", row_sep: "\r\n")
    assert_not_nil(csv)
    assert_instance_of(CSV, csv)
    assert_not_predicate(csv, :closed?)
    csv.close
    assert_predicate(csv, :closed?)

    ret = CSV.open(@path) do |new_csv|
      csv = new_csv
      assert_instance_of(CSV, new_csv)
      "Return value."
    end
    assert_predicate(csv, :closed?)
    assert_equal("Return value.", ret)
  end

  def test_open_encoding_valid
    # U+1F600 GRINNING FACE
    # U+1F601 GRINNING FACE WITH SMILING EYES
    File.open(@path, "w") do |file|
      file << "\u{1F600},\u{1F601}"
    end
    CSV.open(@path, encoding: "utf-8") do |csv|
      assert_equal([["\u{1F600}", "\u{1F601}"]],
                   csv.to_a)
    end
  end

  def test_open_encoding_invalid
    # U+1F600 GRINNING FACE
    # U+1F601 GRINNING FACE WITH SMILING EYES
    File.open(@path, "w") do |file|
      file << "\u{1F600},\u{1F601}"
    end
    CSV.open(@path, encoding: "EUC-JP") do |csv|
      error = assert_raise(CSV::MalformedCSVError) do
        csv.shift
      end
      assert_equal("Invalid byte sequence in EUC-JP in line 1.",
                   error.message)
    end
  end

  def test_open_encoding_nonexistent
    _output, error = capture_io do
      CSV.open(@path, encoding: "nonexistent") do
      end
    end
    assert_equal("path:0: warning: Unsupported encoding nonexistent ignored\n",
                 error.gsub(/\A.+:\d+: /, "path:0: "))
  end

  def test_open_encoding_utf_8_with_bom
    # U+FEFF ZERO WIDTH NO-BREAK SPACE, BOM
    # U+1F600 GRINNING FACE
    # U+1F601 GRINNING FACE WITH SMILING EYES
    File.open(@path, "w") do |file|
      file << "\u{FEFF}\u{1F600},\u{1F601}"
    end
    CSV.open(@path, encoding: "bom|utf-8") do |csv|
      assert_equal([["\u{1F600}", "\u{1F601}"]],
                   csv.to_a)
    end
  end

  def test_parse
    data = File.binread(@path)
    assert_equal( @expected,
                  CSV.parse(data, col_sep: "\t", row_sep: "\r\n") )

    CSV.parse(data, col_sep: "\t", row_sep: "\r\n") do |row|
      assert_equal(@expected.shift, row)
    end
  end

  def test_parse_line
    row = CSV.parse_line("1;2;3", col_sep: ";")
    assert_not_nil(row)
    assert_instance_of(Array, row)
    assert_equal(%w{1 2 3}, row)

    # shortcut interface
    row = "1;2;3".parse_csv(col_sep: ";")
    assert_not_nil(row)
    assert_instance_of(Array, row)
    assert_equal(%w{1 2 3}, row)
  end

  def test_parse_line_with_empty_lines
    assert_equal(nil,       CSV.parse_line(""))  # to signal eof
    assert_equal(Array.new, CSV.parse_line("\n1,2,3"))
  end

  def test_parse_header_only
    table = CSV.parse("a,b,c", headers: true)
    assert_equal([
                   ["a", "b", "c"],
                   [],
                 ],
                 [
                   table.headers,
                   table.each.to_a,
                 ])
  end

  def test_read_and_readlines
    assert_equal( @expected,
                  CSV.read(@path, col_sep: "\t", row_sep: "\r\n") )
    assert_equal( @expected,
                  CSV.readlines(@path, col_sep: "\t", row_sep: "\r\n") )


    data = CSV.open(@path, col_sep: "\t", row_sep: "\r\n") do |csv|
      csv.read
    end
    assert_equal(@expected, data)
    data = CSV.open(@path, col_sep: "\t", row_sep: "\r\n") do |csv|
      csv.readlines
    end
    assert_equal(@expected, data)
  end

  def test_table
    table = CSV.table(@path, col_sep: "\t", row_sep: "\r\n")
    assert_instance_of(CSV::Table, table)
    assert_equal([[:"1", :"2", :"3"], [4, 5, nil]], table.to_a)
  end

  def test_shift  # aliased as gets() and readline()
    CSV.open(@path, "rb+", col_sep: "\t", row_sep: "\r\n") do |csv|
      assert_equal(@expected.shift, csv.shift)
      assert_equal(@expected.shift, csv.shift)
      assert_equal(nil, csv.shift)
    end
  end

  def test_enumerators_are_supported
    CSV.open(@path, col_sep: "\t", row_sep: "\r\n") do |csv|
      enum = csv.each
      assert_instance_of(Enumerator, enum)
      assert_equal(@expected.shift, enum.next)
    end
  end

  def test_shift_removes_from_each
    CSV.open(@path, col_sep: "\t", row_sep: "\r\n") do |csv|
      assert_equal(@expected.shift, csv.shift)
      assert_equal(@expected.count, csv.count)
    end
  end

  def test_each_consumes
    CSV.open(@path, col_sep: "\t", row_sep: "\r\n") do |csv|
      csv.each do end
      assert_equal(0, csv.count)
    end
  end

  def test_nil_is_not_acceptable
    assert_raise_with_message ArgumentError, "Cannot parse nil as CSV" do
      CSV.new(nil)
    end
  end

  def test_open_handles_prematurely_closed_file_descriptor_gracefully
    assert_nothing_raised(Exception) do
      CSV.open(@path) do |csv|
        csv.close
      end
    end
  end

  ### Test Read and Write Interface ###

  def test_filter
    assert_respond_to(CSV, :filter)

    expected = [[1, 2, 3], [4, 5]]
    CSV.filter( "1;2;3\n4;5\n", (result = String.new),
                in_col_sep: ";", out_col_sep: ",",
                converters: :all ) do |row|
      assert_equal(row, expected.shift)
      row.map! { |n| n * 2 }
      row << "Added\r"
    end
    assert_equal("2,4,6,\"Added\r\"\n8,10,\"Added\r\"\n", result)
  end

  def test_instance
    csv = String.new

    first = nil
    assert_nothing_raised(Exception) do
      first =  CSV.instance(csv, col_sep: ";")
      first << %w{a b c}
    end

    assert_equal("a;b;c\n", csv)

    second = nil
    assert_nothing_raised(Exception) do
      second =  CSV.instance(csv, col_sep: ";")
      second << [1, 2, 3]
    end

    assert_equal(first.object_id, second.object_id)
    assert_equal("a;b;c\n1;2;3\n", csv)

    # shortcuts
    assert_equal(STDOUT, CSV.instance.instance_eval { @io })
    assert_equal(STDOUT, CSV { |new_csv| new_csv.instance_eval { @io } })
  end

  def test_options_are_not_modified
    opt = {}.freeze
    assert_nothing_raised {  CSV.foreach(@path, opt)       }
    assert_nothing_raised {  CSV.open(@path, opt){}        }
    assert_nothing_raised {  CSV.parse("", opt)            }
    assert_nothing_raised {  CSV.parse_line("", opt)       }
    assert_nothing_raised {  CSV.read(@path, opt)          }
    assert_nothing_raised {  CSV.readlines(@path, opt)     }
    assert_nothing_raised {  CSV.table(@path, opt)         }
    assert_nothing_raised {  CSV.generate(opt){}           }
    assert_nothing_raised {  CSV.generate_line([], opt)    }
    assert_nothing_raised {  CSV.filter("", "", opt){}     }
    assert_nothing_raised {  CSV.instance("", opt)         }
  end
end
