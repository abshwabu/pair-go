package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Response defines the standardized JSON envelope for all API responses.
// Success: { "data": ..., "meta": ..., "error": null }
// Failure: { "data": null, "meta": null, "error": { "code": ..., "message": ... } }
type Response struct {
	Data  any       `json:"data"`
	Meta  any       `json:"meta"`
	Error *APIError `json:"error"`
}

// APIError encapsulates standard API error details.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// RespondJSON writes a standardized success JSON response.
func RespondJSON(w http.ResponseWriter, status int, data any, meta any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)

	resp := Response{
		Data:  data,
		Meta:  meta,
		Error: nil,
	}

	_ = json.NewEncoder(w).Encode(resp)
}

// RespondError writes a standardized failure JSON response.
func RespondError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)

	resp := Response{
		Data: nil,
		Meta: nil,
		Error: &APIError{
			Code:    code,
			Message: message,
		},
	}

	_ = json.NewEncoder(w).Encode(resp)
}

// OK is a shared response helper writing a successful JSON envelope.
func OK(w http.ResponseWriter, status int, data any, meta ...any) {
	var m any
	if len(meta) > 0 {
		m = meta[0]
	}
	RespondJSON(w, status, data, m)
}

// Fail is a shared response helper writing an error JSON envelope with code and message.
func Fail(w http.ResponseWriter, status int, code, message string) {
	RespondError(w, status, code, message)
}

// ValidationError writes a standardized 400 Bad Request validation failure.
func ValidationError(w http.ResponseWriter, message string) {
	Fail(w, http.StatusBadRequest, "VALIDATION_ERROR", message)
}

// DecodeJSON decodes a JSON request body into dst, strictly rejecting unknown fields.
func DecodeJSON(r *http.Request, dst any) error {
	if r.Body == nil {
		return errors.New("request body cannot be empty")
	}

	// Limit body size to 1MB to prevent DOS attacks
	maxBytesReader := http.MaxBytesReader(nil, r.Body, 1048576)
	dec := json.NewDecoder(maxBytesReader)
	dec.DisallowUnknownFields()

	err := dec.Decode(dst)
	if err != nil {
		var syntaxError *json.SyntaxError
		var unmarshalTypeError *json.UnmarshalTypeError

		switch {
		case errors.As(err, &syntaxError):
			return fmt.Errorf("malformed JSON at position %d", syntaxError.Offset)
		case errors.Is(err, io.ErrUnexpectedEOF):
			return errors.New("malformed JSON")
		case errors.As(err, &unmarshalTypeError):
			return fmt.Errorf("invalid value for field %q at position %d", unmarshalTypeError.Field, unmarshalTypeError.Offset)
		case strings.HasPrefix(err.Error(), "json: unknown field "):
			fieldName := strings.TrimPrefix(err.Error(), "json: unknown field ")
			return fmt.Errorf("unknown field %s", fieldName)
		case errors.Is(err, io.EOF):
			return errors.New("request body cannot be empty")
		case err.Error() == "http: request body too large":
			return errors.New("request body exceeds maximum allowed size (1MB)")
		default:
			return err
		}
	}

	if dec.More() {
		return errors.New("request body must contain only a single JSON object")
	}

	return nil
}
