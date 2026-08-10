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

    test "E-strings with backslash escapes do not leak" do
      n = SQLFingerprint.normalize(~S(SELECT * FROM u WHERE name = E'O\'Brien'))
      refute n =~ "brien"
      refute n =~ ~r/[a-z]{2,}'/
    end

    test "dollar-quoted strings do not leak (empty and tagged)" do
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE b = $$my secret$$") =~ "secret"
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE b = $tag$leaky secret$tag$") =~ "leaky"
    end

    test "scientific and decimal numerics do not leak" do
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE x = 1e5") =~ ~r/\d/
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE bal = 1.5e10") =~ ~r/\d/
    end

    test "params are not mistaken for dollar-quoted strings" do
      assert SQLFingerprint.normalize("SELECT * FROM u WHERE a = $1 AND b = $2") ==
               "select * from u where a = $? and b = $?"
    end

    test "numeric IN-lists collapse arity like param lists" do
      a = SQLFingerprint.fingerprint("SELECT * FROM u WHERE id IN (1, 2, 3)")
      b = SQLFingerprint.fingerprint("SELECT * FROM u WHERE id IN (1, 2)")
      assert a == b
    end

    test "identifiers containing digits survive" do
      n = SQLFingerprint.normalize("SELECT line1, t2.id FROM users_2024 t2")
      assert n =~ "line1"
      assert n =~ "users_2024"
      assert n =~ "t2"
    end
  end
end
