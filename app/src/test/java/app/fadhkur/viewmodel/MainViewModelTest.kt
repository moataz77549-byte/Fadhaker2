package app.fadhkur.viewmodel

import org.junit.Assert.*
import org.junit.Test

class MainViewModelTest {

    @Test
    fun mainViewModel_initialStateIsValid() {
        val vm = MainViewModel()
        assertNotNull(vm.favorites.value)
        assertTrue(vm.favorites.value.isNotEmpty())
        assertNotNull(vm.downloads.value)
        assertNotNull(vm.playlists.value)
    }

    @Test
    fun toggleFavorite_addsAndRemovesItem() {
        val vm = MainViewModel()
        val testId = "test_item_99"

        // Ensure not present
        assertFalse(vm.favorites.value.contains(testId))

        // Add
        vm.toggleFavorite(testId)
        assertTrue(vm.favorites.value.contains(testId))

        // Remove
        vm.toggleFavorite(testId)
        assertFalse(vm.favorites.value.contains(testId))
    }

    @Test
    fun playlists_createAndDeleteWorks() {
        val vm = MainViewModel()
        val initialCount = vm.playlists.value.size

        vm.createPlaylist("ورد الصباح")
        assertEquals(initialCount + 1, vm.playlists.value.size)

        val created = vm.playlists.value.last()
        assertEquals("ورد الصباح", created.name)

        vm.deletePlaylist(created.id)
        assertEquals(initialCount, vm.playlists.value.size)
    }

    @Test
    fun downloads_deleteWorks() {
        val vm = MainViewModel()
        vm.startDownload(1, "سورة الفاتحة")
        val dl = vm.downloads.value.first()
        assertEquals(1, dl.surahNumber)
        assertTrue(dl.expectedSha256.isNotBlank())

        vm.deleteDownload(dl.id)
        assertFalse(vm.downloads.value.any { it.id == dl.id })
    }
}
