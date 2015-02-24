// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <objc/runtime.h>

#import "UnitTest.h"

#define kSystemPathPrefix "/System/"
#define kLibraryPathPrefix "/Library/"
#define kUsrPathPrefix "/usr/"
#define kTestMethodPrefix "test"

@interface UnitTest ()
@property(nonatomic, readonly) NSUInteger numberOfSuccesses;
@property(nonatomic, readonly) NSUInteger numberOfFailures;
- (id) initWithAbortOnFailure:(BOOL)abortOnFailure;
+ (NSUInteger) runTests:(NSArray*)filter abortOnFailure:(BOOL)abortOnFailure;
@end

@implementation UnitTest

@synthesize numberOfSuccesses=_successes, numberOfFailures=_failures;

- (id) initWithAbortOnFailure:(BOOL)abortOnFailure {
  if ((self = [super init])) {
    _abortOnFailure = abortOnFailure;
  }
  return self;
}

- (void) setUp {
}

- (void) cleanUp {
}

- (void) reportResult:(BOOL)success {
  if(success) {
    _successes += 1;
  } else {
    _failures += 1;
    if(_abortOnFailure) {
      abort();
    }
  }
}

static NSComparisonResult _ClassSortFunction(Class class1, Class class2, void* context) {
  return [NSStringFromClass(class1) caseInsensitiveCompare:NSStringFromClass(class2)];
}

static NSComparisonResult _SelectorSortFunction(NSValue* value1, NSValue* value2, void* context) {
  return [NSStringFromSelector([value1 pointerValue]) caseInsensitiveCompare:NSStringFromSelector([value2 pointerValue])];
}

+ (NSUInteger) runTests:(NSArray*)filter abortOnFailure:(BOOL)abortOnFailure {
  NSUInteger failures = 0;
  if (self == [UnitTest class]) {
    NSMutableArray* array = [[NSMutableArray alloc] init];
    unsigned int count1;
    const char** images = objc_copyImageNames(&count1);
    for (unsigned int i1 = 0; i1 < count1; ++i1) {
      if (strncmp(images[i1], kSystemPathPrefix, strlen(kSystemPathPrefix)) == 0) {
        continue;
      }
      if (strncmp(images[i1], kLibraryPathPrefix, strlen(kLibraryPathPrefix)) == 0) {
        continue;
      }
      if (strncmp(images[i1], kUsrPathPrefix, strlen(kUsrPathPrefix)) == 0) {
        continue;
      }
      unsigned int count2;
      const char** classes = objc_copyClassNamesForImage(images[i1], &count2);
      for (unsigned int i2 = 0; i2 < count2; ++i2) {
        Class class = objc_getClass(classes[i2]);
        do {
          class = class_getSuperclass(class);
        } while (class && (class != self));
        if (class == nil) {
          continue;
        }
        class = objc_getClass(classes[i2]);
        BOOL runTests = YES;
        for (NSString* entry in filter) {
          if (![entry hasPrefix:@"+" kTestMethodPrefix] && ![entry hasPrefix:@"-" kTestMethodPrefix]) {
            runTests = NO;
            if ([entry isEqualToString:NSStringFromClass(class)]) {
              runTests = YES;
              break;
            }
          }
        }
        if (runTests) {
          [array addObject:class];
        }
      }
    }
    [array sortUsingFunction:_ClassSortFunction context:NULL];
    for (Class class in array) {
      failures += [class runTests:filter abortOnFailure:abortOnFailure];
    }
    [array release];
  } else {
    NSMutableArray* array = [[NSMutableArray alloc] init];
    unsigned int count;
    Method* methods = class_copyMethodList(self, &count);
    for (unsigned int i = 0; i < count; ++i) {
      SEL method = method_getName(methods[i]);
      if (strncmp(sel_getName(method), kTestMethodPrefix, strlen(kTestMethodPrefix)) == 0) {
        BOOL runTest = YES;
        for (NSString* entry in filter) {
          if ([entry hasPrefix:@"+"]) {
            runTest = NO;
            if ([[entry substringFromIndex:1] isEqualToString:NSStringFromSelector(method)]) {
              runTest = YES;
              break;
            }
          } else if ([entry hasPrefix:@"-"] && [[entry substringFromIndex:1] isEqualToString:NSStringFromSelector(method)]) {
            runTest = NO;
          }
        }
        if (runTest) {
          [array addObject:[NSValue valueWithPointer:method]];
        }
      }
    }
    [array sortUsingFunction:_SelectorSortFunction context:NULL];
    for (NSValue* value in array) {
      SEL method = [value pointerValue];
      LOG_INFO(@"Running unit test -[%s %s]", class_getName(self), sel_getName(method));
      @try {
        NSAutoreleasePool* pool = [NSAutoreleasePool new];
        UnitTest* test = [[self alloc] initWithAbortOnFailure:abortOnFailure];
        @try {
          [test setUp];
          if (test.numberOfFailures == 0) {
            [test performSelector:method];
          }
          failures += test.numberOfFailures;
        }
        @catch (NSException* exception) {
          LOG_EXCEPTION(exception);
          failures += 1;
        }
        @finally {
          [test cleanUp];
        }
        [test release];
        [pool drain];
      }
      @catch (NSException* exception) {
        LOG_EXCEPTION(exception);
        failures += 1;
      }
    }
    [array release];
  }
  return failures;
}

@end

int main(int argc, const char* argv[]) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  NSMutableArray* arguments = [[NSMutableArray alloc] initWithArray:[[NSProcessInfo processInfo] arguments]];
  [arguments removeObjectAtIndex:0];
  NSUInteger failures = [UnitTest runTests:arguments
                            abortOnFailure:([[[NSProcessInfo processInfo] environment] objectForKey:@"AbortOnFailure"] ? YES : NO)];
  [arguments release];
  [pool release];
  return failures;
}
