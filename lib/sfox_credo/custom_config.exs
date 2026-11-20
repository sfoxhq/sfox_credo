%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {SfoxCredo.Check.Design.EctoMigrationTimestamps, []},
          {SfoxCredo.Check.Warning.AvoidAtomToString, []},
          {SfoxCredo.Check.Warning.LoggerMessageInspect, []},
          {SfoxCredo.Check.Warning.LoggerMetadataInspect, []}
        ]
      }
    }
  ]
}
