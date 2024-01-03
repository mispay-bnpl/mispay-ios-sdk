# mispay-ios-sdk
### Configuration

Our web payment integration requires the location of the user. Therefore we will add the privacy key of `NSLocationWhenInUseUsageDescription` into the app's' `Info.plist`.

### Usage

```swift
MISPay.checkout(viewControllerToPresent, url) { message in
    // Handle the message
}
```

## Integration
This SDK is to allow MIS-Pay merchants seamlessly integrate with MIS-Pay payment gateway.

A detailed integration documentation be found [here](https://cdn.mispay.co/common/documents/Integration_Guide.pdf).

Also if you are working on a different platform, you can find the SDKs for other platforms [here](https://github.com/mispay-bnpl?tab=repositories).