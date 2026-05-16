/**
 * @description Shared utility functions for the Customer 360 application.
 *              Formatters, sorting, CSV export, seeded random, health color helpers.
 * @author Yousef A
 * @date 2026-03-05
 * @jira BIZ-80363
 */

import {
    HEALTH_THRESHOLDS,
    HEALTH_COLORS,
    HEALTH_LABELS
} from 'c/customer360Constants';

// ─── Salesforce ID Validation ────────────────────────────────────────────────

/**
 * Checks whether a string is a valid Salesforce 15- or 18-character Id.
 * Used to decide whether to call Apex (real SF Id) or skip straight to mock data.
 * @param {string} id - The value to test
 * @returns {boolean} true if the value matches a Salesforce Id pattern
 */
export function isSalesforceId(id) {
    if (!id || typeof id !== 'string') return false;
    return /^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(id);
}

// ─── Seeded Random Number Generator ──────────────────────────────────────────

/**
 * Creates a seeded pseudo-random number generator (linear congruential).
 * Same seed always produces the same sequence of numbers.
 * @param {number|string} seed - Numeric seed or string to hash
 * @returns {Function} Function that returns next random number [0, 1)
 */
export function seededRandom(seed) {
    let s = typeof seed === 'string' ? hashString(seed) : seed;
    return function next() {
        s = (s * 1664525 + 1013904223) & 0xffffffff;
        return (s >>> 0) / 0xffffffff;
    };
}

/**
 * Simple string hash (djb2 algorithm).
 * @param {string} str - String to hash
 * @returns {number} Hash value
 */
export function hashString(str) {
    let hash = 5381;
    for (let i = 0; i < str.length; i++) {
        hash = ((hash << 5) + hash + str.charCodeAt(i)) & 0xffffffff;
    }
    return hash >>> 0;
}

// ─── Formatting ──────────────────────────────────────────────────────────────

/**
 * Format number as currency (USD).
 * @param {number} value
 * @param {boolean} [compact=false] - Use compact notation (e.g., $1.2M)
 * @returns {string}
 */
export function formatCurrency(value, compact = false) {
    if (value == null || isNaN(value)) return '$0';
    if (compact) {
        if (Math.abs(value) >= 1000000) {
            return '$' + (value / 1000000).toFixed(1) + 'M';
        }
        if (Math.abs(value) >= 1000) {
            return '$' + (value / 1000).toFixed(0) + 'K';
        }
    }
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
    }).format(value);
}

/**
 * Format date to readable string.
 * @param {string|Date} dateValue
 * @param {string} [format='short'] - 'short' (Mar 5, 2026), 'long' (March 5, 2026), 'relative' (5 days ago)
 * @returns {string}
 */
export function formatDate(dateValue, format = 'short') {
    if (!dateValue) return '';
    const date = dateValue instanceof Date ? dateValue : new Date(dateValue);
    if (isNaN(date.getTime())) return '';

    if (format === 'relative') {
        return getRelativeTime(date);
    }

    const options = format === 'long'
        ? { year: 'numeric', month: 'long', day: 'numeric' }
        : { year: 'numeric', month: 'short', day: 'numeric' };

    return date.toLocaleDateString('en-US', options);
}

/**
 * Get relative time string (e.g., "5 days ago", "in 3 weeks").
 * @param {Date} date
 * @returns {string}
 */
function getRelativeTime(date) {
    const now = new Date();
    const diffMs = now - date;
    const diffDays = Math.floor(Math.abs(diffMs) / (1000 * 60 * 60 * 24));
    const isFuture = diffMs < 0;
    const prefix = isFuture ? 'in ' : '';
    const suffix = isFuture ? '' : ' ago';

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return isFuture ? 'Tomorrow' : 'Yesterday';
    if (diffDays < 7) return `${prefix}${diffDays} days${suffix}`;
    if (diffDays < 30) {
        const weeks = Math.floor(diffDays / 7);
        return `${prefix}${weeks} week${weeks > 1 ? 's' : ''}${suffix}`;
    }
    if (diffDays < 365) {
        const months = Math.floor(diffDays / 30);
        return `${prefix}${months} month${months > 1 ? 's' : ''}${suffix}`;
    }
    const years = Math.floor(diffDays / 365);
    return `${prefix}${years} year${years > 1 ? 's' : ''}${suffix}`;
}

/**
 * Format number as percentage.
 * @param {number} value
 * @param {number} [decimals=0]
 * @returns {string}
 */
export function formatPercent(value, decimals = 0) {
    if (value == null || isNaN(value)) return '0%';
    return value.toFixed(decimals) + '%';
}

/**
 * Format number with commas.
 * @param {number} value
 * @returns {string}
 */
export function formatNumber(value) {
    if (value == null || isNaN(value)) return '0';
    return new Intl.NumberFormat('en-US').format(value);
}

// ─── Health Score Helpers ────────────────────────────────────────────────────

/**
 * Get color for a health score value.
 * @param {number} score - 0 to 100
 * @returns {string} Hex color
 */
export function getHealthColor(score) {
    if (score >= HEALTH_THRESHOLDS.GOOD) return HEALTH_COLORS.GOOD;
    if (score >= HEALTH_THRESHOLDS.FAIR) return HEALTH_COLORS.FAIR;
    if (score >= HEALTH_THRESHOLDS.POOR) return HEALTH_COLORS.POOR;
    return HEALTH_COLORS.CRITICAL;
}

/**
 * Get label for a health score value.
 * @param {number} score - 0 to 100
 * @returns {string} Label text
 */
export function getHealthLabel(score) {
    if (score >= HEALTH_THRESHOLDS.GOOD) return HEALTH_LABELS.GOOD;
    if (score >= HEALTH_THRESHOLDS.FAIR) return HEALTH_LABELS.FAIR;
    if (score >= HEALTH_THRESHOLDS.POOR) return HEALTH_LABELS.POOR;
    return HEALTH_LABELS.CRITICAL;
}

/**
 * Determine trend direction from two values.
 * @param {number} current
 * @param {number} previous
 * @param {number} [threshold=2] - Minimum diff to register as a trend
 * @returns {string} 'up' | 'down' | 'stable'
 */
export function getHealthTrend(current, previous, threshold = 2) {
    const diff = current - previous;
    if (diff > threshold) return 'up';
    if (diff < -threshold) return 'down';
    return 'stable';
}

/**
 * Get risk level string from health score.
 * @param {number} score
 * @returns {string} 'low' | 'medium' | 'high' | 'critical'
 */
export function getRiskLevel(score) {
    if (score >= HEALTH_THRESHOLDS.GOOD) return 'low';
    if (score >= HEALTH_THRESHOLDS.FAIR) return 'medium';
    if (score >= HEALTH_THRESHOLDS.POOR) return 'high';
    return 'critical';
}

// ─── Sorting ─────────────────────────────────────────────────────────────────

/**
 * Sort an array of objects by a given field.
 * @param {Array} data
 * @param {string} field
 * @param {string} [direction='asc'] - 'asc' or 'desc'
 * @returns {Array} Sorted copy
 */
export function sortData(data, field, direction = 'asc') {
    if (!data || !data.length) return [];
    const multiplier = direction === 'asc' ? 1 : -1;
    return [...data].sort((a, b) => {
        const valA = a[field] != null ? a[field] : '';
        const valB = b[field] != null ? b[field] : '';
        if (typeof valA === 'string') {
            return multiplier * valA.localeCompare(valB);
        }
        return multiplier * (valA - valB);
    });
}

// ─── CSV Export ──────────────────────────────────────────────────────────────

/**
 * Export data as CSV file download.
 * @param {Array<Object>} data - Array of row objects
 * @param {Array<{label: string, fieldName: string}>} columns - Column definitions
 * @param {string} [filename='export.csv']
 */
export function csvExport(data, columns, filename = 'export.csv') {
    if (!data || !data.length || !columns || !columns.length) return;

    const headers = columns.map(c => `"${c.label}"`).join(',');
    const rows = data.map(row =>
        columns.map(col => {
            const val = row[col.fieldName];
            if (val == null) return '';
            const str = String(val).replace(/"/g, '""');
            return `"${str}"`;
        }).join(',')
    );

    const csv = [headers, ...rows].join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

// ─── ID Generator ────────────────────────────────────────────────────────────

/**
 * Generate a prefixed ID string.
 * @param {string} prefix
 * @param {number} num
 * @returns {string}
 */
export function generateId(prefix, num) {
    return `${prefix}-${String(num).padStart(3, '0')}`;
}

// ─── Date Helpers ────────────────────────────────────────────────────────────

/**
 * Get number of days between two dates.
 * @param {Date|string} date1
 * @param {Date|string} date2
 * @returns {number}
 */
export function daysBetween(date1, date2) {
    const d1 = new Date(date1);
    const d2 = new Date(date2);
    return Math.floor(Math.abs(d2 - d1) / (1000 * 60 * 60 * 24));
}

/**
 * Add days to a date.
 * @param {Date|string} date
 * @param {number} days
 * @returns {Date}
 */
export function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

/**
 * Get date N months ago from now.
 * @param {number} months
 * @returns {Date}
 */
export function monthsAgo(months) {
    const d = new Date();
    d.setMonth(d.getMonth() - months);
    return d;
}

// ─── Misc Helpers ────────────────────────────────────────────────────────────

/**
 * Clamp a number between min and max.
 * @param {number} val
 * @param {number} min
 * @param {number} max
 * @returns {number}
 */
export function clamp(val, min, max) {
    return Math.min(Math.max(val, min), max);
}

/**
 * Pick a random item from an array using a seeded random function.
 * @param {Array} arr
 * @param {Function} rng - Seeded random function returning [0, 1)
 * @returns {*}
 */
export function pickRandom(arr, rng) {
    return arr[Math.floor(rng() * arr.length)];
}

/**
 * Pick N unique random items from an array.
 * @param {Array} arr
 * @param {number} n
 * @param {Function} rng
 * @returns {Array}
 */
export function pickRandomN(arr, n, rng) {
    const shuffled = [...arr].sort(() => rng() - 0.5);
    return shuffled.slice(0, Math.min(n, arr.length));
}

/**
 * Generate a random integer between min and max (inclusive).
 * @param {number} min
 * @param {number} max
 * @param {Function} rng
 * @returns {number}
 */
export function randomInt(min, max, rng) {
    return Math.floor(rng() * (max - min + 1)) + min;
}

/**
 * Generate a random float between min and max.
 * @param {number} min
 * @param {number} max
 * @param {Function} rng
 * @returns {number}
 */
export function randomFloat(min, max, rng) {
    return rng() * (max - min) + min;
}