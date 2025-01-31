const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
pub const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("rpmalloc.h");
});

pub const max_alignment = 256 * 1024;

pub const GlobalStatistics = extern struct {
    /// Current amount of virtual memory mapped, all of which might not have been committed (only if
    /// ENABLE_STATISTICS=1)
    mapped: usize,
    /// Peak amount of virtual memory mapped, all of which might not have been committed (only if ENABLE_STATISTICS=1)
    mapped_peak: usize,
    /// Current amount of memory in global caches for small and medium sizes (<32KiB)
    cached: usize,
    /// Current amount of memory allocated in huge allocations, i.e larger than LARGE_SIZE_LIMIT which is 2MiB by
    /// default (only if ENABLE_STATISTICS=1)
    huge_alloc: usize,
    /// Peak amount of memory allocated in huge allocations, i.e larger than LARGE_SIZE_LIMIT which is 2MiB by default
    /// (only if ENABLE_STATISTICS=1)
    huge_alloc_peak: usize,
    /// Total amount of memory mapped since initialization (only if ENABLE_STATISTICS=1)
    mapped_total: usize,
    /// Total amount of memory unmapped since initialization  (only if ENABLE_STATISTICS=1)
    unmapped_total: usize,
};

pub const SpanStatistics = extern struct {
    /// Currently used number of spans
    current: usize,
    /// High water mark of spans used
    peak: usize,
    /// Number of spans transitioned to global cache
    to_global: usize,
    /// Number of spans transitioned from global cache
    from_global: usize,
    /// Number of spans transitioned to thread cache
    to_cache: usize,
    /// Number of spans transitioned from thread cache
    from_cache: usize,
    /// Number of spans transitioned to reserved state
    to_reserved: usize,
    /// Number of spans transitioned from reserved state
    from_reserved: usize,
    /// Number of raw memory map calls (not hitting the reserve spans but resulting in actual OS mmap calls)
    map_calls: usize,
};

pub const SizeClassStatistics = extern struct {
    /// Current number of allocations
    alloc_current: usize,
    /// Peak number of allocations
    alloc_peak: usize,
    /// Total number of allocations
    alloc_total: usize,
    /// Total number of frees
    free_total: usize,
    /// Number of spans transitioned to cache
    spans_to_cache: usize,
    /// Number of spans transitioned from cache
    spans_from_cache: usize,
    /// Number of spans transitioned from reserved state
    spans_from_reserved: usize,
    /// Number of raw memory map calls (not hitting the reserve spans but resulting in actual OS mmap calls)
    map_calls: usize,
};

pub const ThreadStatistics = extern struct {
    /// Current number of bytes available in thread size class caches for small and medium sizes (<32KiB)
    size_cache: usize,
    /// Current number of bytes available in thread span caches for small and medium sizes (<32KiB)
    span_cache: usize,
    /// Total number of bytes transitioned from thread cache to global cache (only if ENABLE_STATISTICS=1)
    thread_to_global: usize,
    /// Total number of bytes transitioned from global cache to thread cache (only if ENABLE_STATISTICS=1)
    global_to_thread: usize,
    /// Per span count statistics (only if ENABLE_STATISTICS=1)
    span_use: [64]SpanStatistics,
    /// Per size class statistics (only if ENABLE_STATISTICS=1)
    size_use: [128]SizeClassStatistics,
};

pub const Interface = extern struct {
    /// Map memory pages for the given number of bytes. The returned address MUST be aligned to the given alignment,
    /// which will always be either 0 or the span size. The function can store an alignment offset in the offset
    /// variable in case it performs alignment and the returned pointer is offset from the actual start of the memory
    /// region due to this alignment. This alignment offset will be passed to the memory unmap function. The mapped size
    /// can be stored in the mapped_size variable, which will also be passed to the memory unmap function as the release
    /// parameter once the entire mapped region is ready to be released. If you set a memory_map function, you must also
    /// set a memory_unmap function or else the default implementation will be used for both. This function must be
    /// thread safe, it can be called by multiple threads simultaneously.
    memory_map: ?*const fn (size: usize, alignment: usize, offset: *usize, mapped_size: *usize) callconv(.C) void = null,
    /// Commit a range of memory pages
    memory_commit: ?*const fn (address: *anyopaque, size: usize) callconv(.C) void = null,
    /// Decommit a range of memory pages
    memory_decommit: ?*const fn (address: *anyopaque, size: usize) callconv(.C) void = null,
    /// Unmap the memory pages starting at address and spanning the given number of bytes. If you set a memory_unmap
    /// function, you must also set a memory_map function or else the default implementation will be used for both. This
    /// function must be thread safe, it can be called by multiple threads simultaneously.
    memory_unmap: ?*const fn (address: *anyopaque, offset: usize, mapped_size: usize) callconv(.C) void = null,
    /// Called when a call to map memory pages fails (out of memory). If this callback is not set or returns zero the
    /// library will return a null pointer in the allocation call. If this callback returns non-zero the map call will
    /// be retried. The argument passed is the number of bytes that was requested in the map call. Only used if the
    /// default system memory map function is used (memory_map callback is not set).
    map_fail_callback: ?*const fn (size: usize) callconv(.C) c_int = null,
    /// Called when an assert fails, if asserts are enabled. Will use the standard assert() if this is not set.
    error_callback: ?*const fn (message: [*:0]const u8) callconv(.C) void = null,
};

pub const Config = if (builtin.os.tag == .linux) extern struct {
    /// Size of memory pages. The page size MUST be a power of two. All memory mapping
    /// requests to memory_map will be made with size set to a multiple of the page size.
    /// Set to 0 to use the OS default page size.
    page_size: usize = 0,
    /// Enable use of large/huge pages. If this flag is set to non-zero and page size is
    /// zero, the allocator will try to enable huge pages and auto detect the configuration.
    /// If this is set to non-zero and page_size is also non-zero, the allocator will
    /// assume huge pages have been configured and enabled prior to initializing the
    /// allocator.
    /// For Windows, see https://docs.microsoft.com/en-us/windows/desktop/memory/large-page-support
    /// For Linux, see https://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt
    enable_huge_pages: c_int = 0,
    /// Disable decommitting unused pages when allocator determines the memory pressure
    /// is low and there is enough active pages cached. If set to 1, keep all pages committed.
    disable_decommit: c_int = 0,
    /// Allocated pages names for systems supporting it to be able to distinguish among anonymous regions.
    page_name: ?[*:0]const u8 = null,
    /// Allocated huge pages names for systems supporting it to be able to distinguish among anonymous regions.
    huge_page_name: ?[*:0]const u8 = null,
    /// Unmap all memory on finalize if set to 1. Normally you can let the OS unmap all pages
    /// when process exits, but if using rpmalloc in a dynamic library you might want to unmap
    /// all pages when the dynamic library unloads to avoid process memory leaks and bloat.
    unmap_on_finalize: c_int = 0,
    /// Allows to disable the Transparent Huge Page feature on Linux on a process basis,
    /// rather than enabling/disabling system-wise (done via /sys/kernel/mm/transparent_hugepage/enabled).
    /// It can possibly improve performance and reduced allocation overhead in some contexts, albeit
    /// THP is usually enabled by default.
    disable_thp: c_int = 0,
} else extern struct {
    /// Size of memory pages. The page size MUST be a power of two. All memory mapping
    /// requests to memory_map will be made with size set to a multiple of the page size.
    /// Set to 0 to use the OS default page size.
    page_size: usize = 0,
    /// Enable use of large/huge pages. If this flag is set to non-zero and page size is
    /// zero, the allocator will try to enable huge pages and auto detect the configuration.
    /// If this is set to non-zero and page_size is also non-zero, the allocator will
    /// assume huge pages have been configured and enabled prior to initializing the
    /// allocator.
    /// For Windows, see https://docs.microsoft.com/en-us/windows/desktop/memory/large-page-support
    /// For Linux, see https://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt
    enable_huge_pages: c_int = 0,
    /// Disable decommitting unused pages when allocator determines the memory pressure
    /// is low and there is enough active pages cached. If set to 1, keep all pages committed.
    disable_decommit: c_int = 0,
    /// Allocated pages names for systems supporting it to be able to distinguish among anonymous regions.
    page_name: ?[*:0]const u8 = null,
    /// Allocated huge pages names for systems supporting it to be able to distinguish among anonymous regions.
    huge_page_name: ?[*:0]const u8 = null,
    /// Unmap all memory on finalize if set to 1. Normally you can let the OS unmap all pages
    /// when process exits, but if using rpmalloc in a dynamic library you might want to unmap
    /// all pages when the dynamic library unloads to avoid process memory leaks and bloat.
    unmap_on_finalize: c_int = 0,
};

/// Initialize allocator
pub fn init(interface: Interface, config: Config) void {
    _ = c.rpmalloc_initialize_config(@constCast(@ptrCast(&interface)), @constCast(@ptrCast(&config)));
}

/// Deinitialize allocator
pub fn deinit() void {
    c.rpmalloc_finalize();
}

/// Get allocator configuration
pub fn getConfig() *const Config {
    return @ptrCast(c.rpmalloc_config());
}

/// Initialize allocator for calling thread
pub fn initThread() void {
    c.rpmalloc_thread_initialize();
}

/// Deinitialize allocator for calling thread
pub fn deinitThread() void {
    c.rpmalloc_thread_finalize();
}

/// Perform deferred deallocations pending for the calling thread heap
pub fn threadCollect() void {
    c.rpmalloc_thread_collect();
}

/// Query if allocator is initialized for calling thread
pub fn isThreadInitialized() bool {
    return c.rpmalloc_is_thread_initialized() == 1;
}

/// Get per-thread statistics
pub fn threadStatistics() ThreadStatistics {
    var stats: ThreadStatistics = undefined;
    c.rpmalloc_thread_statistics(@ptrCast(&stats));
    return stats;
}

/// Get global statistics
pub fn globalStatistics() GlobalStatistics {
    var stats: GlobalStatistics = undefined;
    c.rpmalloc_thread_statistics(@ptrCast(&stats));
    return stats;
}

pub fn allocator() Allocator {
    return .{
        .ptr = undefined,
        .vtable = &.{
            .alloc = struct {
                fn alloc(_: *anyopaque, len: usize, log2_align: u8, _: usize) ?[*]u8 {
                    assert(len > 0);
                    return @ptrCast(c.rpaligned_alloc(@as(u32, 1) << @as(u5, @intCast(log2_align)), len));
                }
            }.alloc,
            .resize = struct {
                fn resize(_: *anyopaque, buf: []u8, _: u8, new_len: usize, _: usize) bool {
                    if (new_len <= buf.len) return true;
                    return new_len <= c.rpmalloc_usable_size(buf.ptr);
                }
            }.resize,
            .free = struct {
                fn free(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
                    c.rpfree(buf.ptr);
                }
            }.free,
        },
    };
}
