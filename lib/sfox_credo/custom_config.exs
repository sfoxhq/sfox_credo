%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {SfoxCredo.Check.Design.EctoMigrationTimestamps, []},
          {SfoxCredo.Check.Readability.DisableWithoutReason, []},
          {SfoxCredo.Check.Warning.AshCallInEnum, []},
          {SfoxCredo.Check.Warning.AvoidAtomToString, []}
        ]
      }
    }
  ]
}
