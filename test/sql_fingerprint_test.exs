defmodule Excessibility.SQLFingerprintTest do
  use ExUnit.Case, async: true

  alias Excessibility.SQLFingerprint

  describe "normalize/1" do
    test "downcases keywords and collapses whitespace" do
      assert SQLFingerprint.normalize("SELECT  *\nFROM   users") == "select * from users"
    end

    test "folds parameter placeholders to $?" do
      assert SQLFingerprint.normalize("SELECT * FROM u WHERE id = $1 AND org = $2") ==
               "select * from u where id = $? and org = $?"
    end

    test "folds IN-list arity so different lengths share a shape" do
      a = SQLFingerprint.normalize("SELECT * FROM u WHERE id IN ($1,$2,$3)")
      b = SQLFingerprint.normalize("SELECT * FROM u WHERE id IN ($1,$2)")
      assert a == b
      assert a =~ "in ($?)"
    end

    test "folds inline numeric and quoted literals to ?" do
      assert SQLFingerprint.normalize("SELECT * FROM u WHERE status = 'active' LIMIT 50") ==
               "select * from u where status = ? limit ?"
    end
  end

  describe "fingerprint/1" do
    test "is stable and prefixed" do
      fp = SQLFingerprint.fingerprint("SELECT * FROM users WHERE id = $1")
      assert fp =~ ~r/^sha256:[0-9a-f]{16}$/
      assert fp == SQLFingerprint.fingerprint("select  *  from users where id = $1")
    end

    test "differs for different query shapes" do
      refute SQLFingerprint.fingerprint("SELECT * FROM a WHERE id = $1") ==
               SQLFingerprint.fingerprint("SELECT * FROM b WHERE id = $1")
    end
  end

  # Property-style leak guard: no digit-run and no quoted literal survives.
  describe "privacy" do
    test "no quoted literal survives normalization" do
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE name = 'Alice O''Brien'") =~ ~r/[a-z]{2,}'/
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE name = 'Alice O''Brien'") =~ "alice"
    end

    test "no multi-digit literal survives" do
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE age = 42 AND ssn = 123456789") =~ ~r/\d{2,}/
    end
  end
end
