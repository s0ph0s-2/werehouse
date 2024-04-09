
--- The data produced by a scraper.
---@alias ScrapedSourceData { raw_image_uri: string, mime_type: string, width: integer, height: integer }

--- ScraperProcess function: given a URI, scrape whatever info is needed for archiving
--- from that website.
---@alias ScraperProcess fun(uri: string): Result<ScrapedSourceData, string>

--- ScraperCanProcess: given a URI, inform the pipeline whether the associated
--- scraper is able to process that URI.
---@alias ScraperCanProcess fun(uri: string): boolean

---@alias Scraper {process_uri: ScraperProcess, can_process_uri: ScraperCanProcess}

---@class ScraperError {description: string}
ScraperError = {
    description = "Something went so wrong that I couldn't even describe it."
}

---@class TempScraperError : ScraperError
function TempScraperError(description)
    local result = {
        description = description,
        type = 0
    }
    setmetatable(result, ScraperError)
end
---@class PermScraperError : ScraperError
function PermScraperError(description)
    local result = {
        description = description,
        type = 1
    }
    setmetatable(result, ScraperError)
end
