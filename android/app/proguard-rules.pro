# WorkManager (Focus Guard's background check) keeps its state in a Room
# database whose generated WorkDatabase_Impl is created by reflection
# through its no-argument constructor. Room 2.6's consumer rule keeps the
# class but, under R8's full mode, not that constructor, and every release
# process would crash at startup (androidx.startup.InitializationProvider:
# NoSuchMethodException WorkDatabase_Impl.<init>). Found in Phase 11C
# qualification of the minified build.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
