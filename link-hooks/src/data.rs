// Copyright © 2022 The Radicle Link Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

use std::{fmt, str::FromStr};

use link_identities::urn::{HasProtocol, Urn};
use multihash::Multihash;

use super::{sealed, Display, IsZero, Updated};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Data<R> {
    pub urn: Urn<R>,
    pub old: R,
    pub new: R,
}

impl<R> Data<R>
where
    R: IsZero + PartialEq,
{
    pub fn updated(&self) -> Updated {
        match (self.old.is_zero(), self.new.is_zero()) {
            (true, true) => Updated::Zero,
            (true, false) => Updated::Created,
            (false, true) => Updated::Deleted,
            (false, false) if self.old != self.new => Updated::Changed,
            _ => Updated::NoChange,
        }
    }
}

impl<R> fmt::Display for Data<R>
where
    R: HasProtocol + fmt::Display,
    for<'a> &'a R: Into<Multihash>,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} ", self.urn)?;

        writeln!(f, "{} {}", self.old, self.new)
    }
}

impl<R> sealed::Sealed for Data<R> {}
impl<R> Display for Data<R>
where
    R: HasProtocol + fmt::Display,
    for<'a> &'a R: Into<Multihash>,
{
    fn display(&self) -> String {
        self.to_string()
    }
}

impl<R, E> FromStr for Data<R>
where
    R: HasProtocol + TryFrom<Multihash, Error = E> + FromStr,
    R::Err: std::error::Error + Send + Sync + 'static,
    E: std::error::Error + Send + Sync + 'static,
{
    type Err = error::Parse<E>;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let mut components = s.split(' ');

        let urn = match components.next() {
            Some(urn) => urn.parse::<Urn<R>>()?,
            None => return Err(error::Parse::Missing("rad:git:<identitifier>[/<path>]")),
        };

        let old = match components.next() {
            Some(old) => old
                .parse::<R>()
                .map_err(|err| error::Parse::Revision(Box::new(err)))?,
            None => return Err(error::Parse::Missing("<old>")),
        };

        let new = match components.next() {
            Some(new) => match new.strip_suffix('\n') {
                None => return Err(error::Parse::Newline(new.to_string())),
                Some(new) => new
                    .parse::<R>()
                    .map_err(|err| error::Parse::Revision(Box::new(err)))?,
            },
            None => return Err(error::Parse::Missing("<new> LF")),
        };

        if let Some(extra) = components.next() {
            return Err(error::Parse::Extra(extra.to_string()));
        }

        Ok(Self { urn, old, new })
    }
}

pub mod error {
    use link_identities::urn;
    use thiserror::Error;

    #[derive(Debug, Error)]
    pub enum Parse<E: std::error::Error + Send + Sync + 'static> {
        #[error("found extra data {0}")]
        Extra(String),
        #[error("missing component {0}")]
        Missing(&'static str),
        #[error("expected newline, but found {0}")]
        Newline(String),
        #[error(transparent)]
        Revision(Box<dyn std::error::Error + Send + Sync + 'static>),
        #[error(transparent)]
        Urn(#[from] urn::error::FromStr<E>),
    }
}
