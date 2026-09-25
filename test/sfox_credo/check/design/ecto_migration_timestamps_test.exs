defmodule SfoxCredo.Check.Design.EctoMigrationTimestampsTest do
  use Credo.Test.Case

  alias SfoxCredo.Check.Design.EctoMigrationTimestamps

  @filename "priv/repo/migrations/20240101000000_create_widgets.exs"

  defp migration(body) do
    """
    defmodule MyApp.Repo.Migrations.CreateWidgets do
      use Ecto.Migration

      def change do
        create table(:widgets) do
    #{body}
        end
      end
    end
    """
  end

  describe "timestamps() call" do
    test "bare timestamps() satisfies the check" do
      """
            add :name, :string
            timestamps()
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end

    test "timestamps() with unrelated options still satisfies the check" do
      """
            timestamps(type: :utc_datetime)
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end

    test "timestamps(updated_at: false) alone reports the missing updated_at column" do
      """
            timestamps(updated_at: false)
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> assert_issue(fn issue -> assert issue.message =~ "missing updated_at column" end)
    end

    test "timestamps(inserted_at: false) alone reports the missing inserted_at column" do
      """
            timestamps(inserted_at: false)
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> assert_issue(fn issue -> assert issue.message =~ "missing inserted_at column" end)
    end

    test "timestamps(inserted_at: false) combined with an explicit inserted_at column is satisfied" do
      """
            timestamps(inserted_at: false)
            add :inserted_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end
  end

  describe "explicit add columns" do
    test "explicit inserted_at and updated_at columns satisfy the check" do
      """
            add :inserted_at, :utc_datetime
            add :updated_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end

    test "missing both columns reports both" do
      """
            add :name, :string
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> assert_issue(fn issue -> assert issue.message =~ "missing both inserted_at and updated_at columns" end)
    end

    test "only inserted_at present reports the missing updated_at column" do
      """
            add :inserted_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> assert_issue(fn issue -> assert issue.message =~ "missing updated_at column" end)
    end

    test "only updated_at present reports the missing inserted_at column" do
      """
            add :updated_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> assert_issue(fn issue -> assert issue.message =~ "missing inserted_at column" end)
    end
  end

  describe "inserted_at/updated_at aliases" do
    test "a configured alias satisfies the check in place of the stock name" do
      """
            add :created_at, :utc_datetime
            add :updated_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps, inserted_at: [:created_at])
      |> refute_issues()
    end

    test "an unconfigured alternate name does not satisfy the check" do
      """
            add :created_at, :utc_datetime
            add :updated_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> assert_issue(fn issue -> assert issue.message =~ "missing inserted_at column" end)
    end

    test "the stock column name is always accepted even when aliases are configured" do
      """
            add :inserted_at, :utc_datetime
            add :updated_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps, inserted_at: [:created_at])
      |> refute_issues()
    end

    test "a disabled timestamps() column can be satisfied by an aliased explicit column" do
      """
            timestamps(updated_at: false)
            add :changed_at, :utc_datetime_usec
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps, updated_at: [:changed_at])
      |> refute_issues()
    end

    test "reports the configured aliases in the issue message" do
      """
            add :updated_at, :utc_datetime
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps, inserted_at: [:created_at])
      |> assert_issue(fn issue -> assert issue.message =~ "inserted_at (or aliases created_at) column" end)
    end
  end

  describe "irrelevant AST shapes" do
    test "alter table is ignored" do
      """
      defmodule MyApp.Repo.Migrations.AlterWidgets do
        use Ecto.Migration

        def change do
          alter table(:widgets) do
            add :description, :string
          end
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end

    test "create table without a do-block is ignored" do
      """
      defmodule MyApp.Repo.Migrations.CreateWidgets do
        use Ecto.Migration

        def change do
          create table(:widgets)
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end
  end

  describe "file relevance" do
    test "non-migration files are ignored regardless of content" do
      """
            add :name, :string
      """
      |> migration()
      |> to_source_file("lib/my_app/widgets.ex")
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end

    test "files under deps/ are ignored even if they look like migrations" do
      """
            add :name, :string
      """
      |> migration()
      |> to_source_file("deps/some_dep/priv/repo/migrations/20240101000000_create_widgets.exs")
      |> run_check(EctoMigrationTimestamps)
      |> refute_issues()
    end

    test "start_after excludes migrations at or before the given timestamp" do
      """
            add :name, :string
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps, start_after: "20240101000000")
      |> refute_issues()
    end

    test "start_after includes migrations strictly after the given timestamp" do
      """
            add :name, :string
      """
      |> migration()
      |> to_source_file(@filename)
      |> run_check(EctoMigrationTimestamps, start_after: "20230101000000")
      |> assert_issue()
    end
  end
end
