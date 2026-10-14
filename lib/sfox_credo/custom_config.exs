%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {SfoxCredo.Check.Design.EctoMigrationTimestamps, []},
          {SfoxCredo.Check.Warning.AvoidAtomToString, []}
        ]
      }
    }
  ]
}
