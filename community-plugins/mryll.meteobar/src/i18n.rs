//! Condition-text, weekday and "today" translations. A plain `match` over a
//! fixed, small string set — no i18n crate, no locale data. Every surface
//! (Waybar tooltip, `--output json`, and through it the Omarchy panel) reads
//! from here, so nothing is translated twice.
//!
//! Adding a language means: a `Language` variant, its code in `from_code`,
//! a condition table like `de_condition_text`, a `short_weekday` arm, a
//! `today` arm, and a completeness test like
//! `every_condition_string_is_translated` (which covers German only).

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Language {
    En,
    De,
}

impl Language {
    /// `--language` wins outright. Otherwise the first set, non-empty
    /// variable of `env` decides — the caller passes `LC_ALL`, `LC_MESSAGES`,
    /// `LANG` in that order, the POSIX precedence gettext uses. Whatever that
    /// variable says is final: `C`, `POSIX`, an unknown language, all resolve
    /// to English without consulting the next variable. An unset environment
    /// is English too.
    pub fn resolve(flag: Option<&str>, env: [Option<&str>; 3]) -> Language {
        if let Some(code) = flag {
            return Self::from_code(code);
        }
        env.into_iter()
            .flatten()
            .map(str::trim)
            .find(|value| !value.is_empty())
            .map(Self::from_code)
            .unwrap_or(Language::En)
    }

    /// POSIX locale strings look like `de_DE.UTF-8` or `de_DE@euro`; only the
    /// language subtag before the first `_`, `.`, or `@` is meaningful here.
    fn primary_subtag(code: &str) -> &str {
        code.split(['_', '.', '@', '-']).next().unwrap_or(code)
    }

    fn from_code(code: &str) -> Language {
        match Self::primary_subtag(code.trim())
            .to_ascii_lowercase()
            .as_str()
        {
            "de" => Language::De,
            _ => Language::En,
        }
    }
}

/// Translate one of the 28 fixed WMO condition strings `icons.rs` owns.
/// `english` must be one of those literals; anything else (there is no other
/// caller) is returned unchanged, same as an untranslated language.
pub fn condition_text(english: &'static str, language: Language) -> &'static str {
    match language {
        Language::En => english,
        Language::De => de_condition_text(english),
    }
}

fn de_condition_text(english: &'static str) -> &'static str {
    match english {
        "Clear sky" => "Klarer Himmel",
        "Mainly clear" => "Überwiegend klar",
        "Partly cloudy" => "Teilweise bewölkt",
        "Overcast" => "Bedeckt",
        "Fog" => "Nebel",
        "Rime fog" => "Raureifnebel",
        "Light drizzle" => "Leichter Nieselregen",
        "Moderate drizzle" => "Mäßiger Nieselregen",
        "Dense drizzle" => "Starker Nieselregen",
        "Freezing drizzle" => "Gefrierender Nieselregen",
        "Dense freezing drizzle" => "Starker gefrierender Nieselregen",
        "Slight rain" => "Leichter Regen",
        "Moderate rain" => "Mäßiger Regen",
        "Heavy rain" => "Starker Regen",
        "Freezing rain" => "Gefrierender Regen",
        "Heavy freezing rain" => "Starker gefrierender Regen",
        "Slight snow" => "Leichter Schneefall",
        "Moderate snow" => "Mäßiger Schneefall",
        "Heavy snow" => "Starker Schneefall",
        "Snow grains" => "Schneegriesel",
        "Slight rain showers" => "Leichte Regenschauer",
        "Moderate rain showers" => "Mäßige Regenschauer",
        "Violent rain showers" => "Heftige Regenschauer",
        "Slight snow showers" => "Leichte Schneeschauer",
        "Heavy snow showers" => "Starke Schneeschauer",
        "Thunderstorm" => "Gewitter",
        "Thunderstorm with hail" => "Gewitter mit Hagel",
        "Thunderstorm with heavy hail" => "Gewitter mit starkem Hagel",
        other => other,
    }
}

/// "Today", for the first row of the panel's daily forecast.
pub fn today(language: Language) -> &'static str {
    match language {
        Language::En => "Today",
        Language::De => "Heute",
    }
}

/// Abbreviated weekday name for the daily forecast (`waybar.rs::short_day_name`
/// and `structured.rs::day_label`). Not chrono's `%a`: that is always English
/// unless the `unstable-locales` feature is on, which is more machinery than
/// 7 fixed abbreviations need.
pub fn short_weekday(weekday: chrono::Weekday, language: Language) -> &'static str {
    use chrono::Weekday::*;
    match language {
        Language::En => match weekday {
            Mon => "Mon",
            Tue => "Tue",
            Wed => "Wed",
            Thu => "Thu",
            Fri => "Fri",
            Sat => "Sat",
            Sun => "Sun",
        },
        Language::De => match weekday {
            Mon => "Mo",
            Tue => "Di",
            Wed => "Mi",
            Thu => "Do",
            Fri => "Fr",
            Sat => "Sa",
            Sun => "So",
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_condition_string_is_translated() {
        for english in crate::icons::all_descriptions() {
            let de = de_condition_text(english);
            assert_ne!(
                de, english,
                "no German translation for condition string {english:?}"
            );
        }
    }

    #[test]
    fn english_is_the_identity_translation() {
        for english in crate::icons::all_descriptions() {
            assert_eq!(condition_text(english, Language::En), english);
        }
    }

    #[test]
    fn spot_check_a_few_german_conditions() {
        assert_eq!(condition_text("Clear sky", Language::De), "Klarer Himmel");
        assert_eq!(condition_text("Overcast", Language::De), "Bedeckt");
        assert_eq!(
            condition_text("Thunderstorm with heavy hail", Language::De),
            "Gewitter mit starkem Hagel"
        );
    }

    const UNSET: [Option<&str>; 3] = [None, None, None];

    #[test]
    fn explicit_flag_wins_over_environment() {
        assert_eq!(
            Language::resolve(Some("de"), [Some("en_US"), Some("en_US"), Some("en_US")]),
            Language::De
        );
        assert_eq!(
            Language::resolve(Some("en"), [Some("de_DE"), Some("de_DE"), Some("de_DE")]),
            Language::En
        );
        // An unknown flag is English, and it still blocks the environment.
        assert_eq!(
            Language::resolve(Some("fr"), [Some("de_DE"), None, None]),
            Language::En
        );
    }

    #[test]
    fn the_first_set_variable_decides() {
        // LC_ALL over LC_MESSAGES over LANG.
        assert_eq!(
            Language::resolve(None, [Some("de_DE"), Some("en_US"), None]),
            Language::De
        );
        assert_eq!(
            Language::resolve(None, [None, Some("de_DE.UTF-8"), Some("en_US.UTF-8")]),
            Language::De
        );
        assert_eq!(
            Language::resolve(None, [None, Some("en_US.UTF-8"), Some("de_DE.UTF-8")]),
            Language::En
        );
        assert_eq!(
            Language::resolve(None, [None, None, Some("de_AT")]),
            Language::De
        );
    }

    #[test]
    fn c_posix_and_unknown_locales_are_english_and_stop_the_search() {
        for base in ["C", "C.UTF-8", "POSIX", "fr_FR.UTF-8", "english"] {
            assert_eq!(
                Language::resolve(None, [None, Some(base), Some("de_DE.UTF-8")]),
                Language::En,
                "{base:?} must not fall through to LANG"
            );
        }
        assert_eq!(
            Language::resolve(None, [Some("fr_FR"), Some("de_DE"), None]),
            Language::En
        );
    }

    #[test]
    fn empty_and_blank_variables_are_skipped() {
        assert_eq!(
            Language::resolve(None, [Some(""), Some("de_DE"), None]),
            Language::De
        );
        assert_eq!(
            Language::resolve(None, [None, Some("  "), Some("de_DE")]),
            Language::De
        );
        assert_eq!(
            Language::resolve(None, [None, Some(" de_DE "), None]),
            Language::De
        );
        assert_eq!(Language::resolve(None, UNSET), Language::En);
    }

    #[test]
    fn region_encoding_and_case_are_ignored() {
        for code in ["DE_ch.UTF-8", "de-DE", "de_DE@euro", "De"] {
            assert_eq!(
                Language::resolve(None, [Some(code), None, None]),
                Language::De,
                "{code:?}"
            );
        }
        assert_eq!(
            Language::resolve(None, [Some("EN-us"), None, Some("de_DE")]),
            Language::En
        );
    }

    #[test]
    fn today_is_translated() {
        assert_eq!(today(Language::En), "Today");
        assert_eq!(today(Language::De), "Heute");
    }

    #[test]
    fn short_weekday_covers_every_day_in_both_languages() {
        use chrono::Weekday::*;
        let expected = [
            (Mon, "Mon", "Mo"),
            (Tue, "Tue", "Di"),
            (Wed, "Wed", "Mi"),
            (Thu, "Thu", "Do"),
            (Fri, "Fri", "Fr"),
            (Sat, "Sat", "Sa"),
            (Sun, "Sun", "So"),
        ];
        for (day, en, de) in expected {
            assert_eq!(short_weekday(day, Language::En), en);
            assert_eq!(short_weekday(day, Language::De), de);
        }
    }
}
