%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {SfoxCredo.Check.Design.EctoMigrationTimestamp, []},
          {SfoxCredo.Check.Warning.AvoidAtomToString, []}
        ]
      }
    }
  ]
}
