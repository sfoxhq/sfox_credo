defmodule SfoxCredo.Plugin.ActivationWarningTest do
  use ExUnit.Case, async: true

  alias Credo.Execution
  alias SfoxCredo.Check.Design.EctoSchemaTimestamp
  alias SfoxCredo.Check.Warning.AvoidAtomToString
  alias SfoxCredo.Plugin.ActivationWarning

  describe "active?/1" do
    test "true when an SfoxCredo check is enabled with params" do
      exec = %Execution{checks: %{enabled: [{AvoidAtomToString, []}]}}

      assert ActivationWarning.active?(exec)
    end

    test "true when an SfoxCredo check is enabled alongside unrelated checks" do
      exec = %Execution{
        checks: %{enabled: [{SomeUnrelatedCheck, []}, {EctoSchemaTimestamp, []}]}
      }

      assert ActivationWarning.active?(exec)
    end

    test "false when no SfoxCredo check is in the enabled list" do
      exec = %Execution{checks: %{enabled: [{SomeUnrelatedCheck, []}]}}

      refute ActivationWarning.active?(exec)
    end

    test "false when the only SfoxCredo check present is explicitly disabled" do
      exec = %Execution{checks: %{enabled: [{AvoidAtomToString, false}]}}

      refute ActivationWarning.active?(exec)
    end

    test "false for an empty enabled list" do
      exec = %Execution{checks: %{enabled: []}}

      refute ActivationWarning.active?(exec)
    end

    test "true when the check set can't be determined" do
      assert ActivationWarning.active?(%Execution{checks: nil})
    end
  end

  describe "call/2" do
    test "returns the execution unchanged when active" do
      exec = %Execution{checks: %{enabled: [{AvoidAtomToString, []}]}}

      assert ActivationWarning.call(exec, []) == exec
    end

    test "returns the execution unchanged and warns when inactive" do
      exec = %Execution{checks: %{enabled: [{SomeUnrelatedCheck, []}]}}

      assert ActivationWarning.call(exec, []) == exec
    end
  end
end
