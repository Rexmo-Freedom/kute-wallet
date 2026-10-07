import AuthenticationServices
import Flutter
import Security
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testRandomFailureDiscardsPartialBytes() {
    let bytes = PasskeyPrfPlugin.ceremonyRandomBytes { count, buffer in
      buffer.initializeMemory(as: UInt8.self, repeating: 0x42, count: count / 2)
      return errSecNotAvailable
    }
    XCTAssertNil(bytes)
  }

  func testSuccessfulRandomReadPreservesAll32Bytes() {
    let bytes = PasskeyPrfPlugin.ceremonyRandomBytes { count, buffer in
      XCTAssertEqual(count, 32)
      buffer.initializeMemory(as: UInt8.self, repeating: 0x42, count: count)
      return errSecSuccess
    }
    XCTAssertEqual(bytes, Data(repeating: 0x42, count: 32))
  }

  func testCancellationHasDistinctChannelCode() {
    let error = NSError(
      domain: ASAuthorizationError.errorDomain,
      code: ASAuthorizationError.canceled.rawValue
    )
    XCTAssertEqual(PasskeyPrfPlugin.authorizationError(error).code, "USER_CANCELLED")
  }

  func testOtherAuthorizationFailuresAreNotCancellation() {
    let error = NSError(
      domain: ASAuthorizationError.errorDomain,
      code: ASAuthorizationError.failed.rawValue
    )
    XCTAssertEqual(PasskeyPrfPlugin.authorizationError(error).code, "PRF_ERROR")
  }

  func testOtherErrorDomainCannotSpoofCancellation() {
    let error = NSError(domain: "another.domain", code: ASAuthorizationError.canceled.rawValue)
    XCTAssertEqual(PasskeyPrfPlugin.authorizationError(error).code, "PRF_ERROR")
  }

}
